export class BodyError extends Error {
  constructor(public status: 400 | 413 | 503) {
    super("Body unavailable");
  }
}

export async function boundedBody(
  stream: ReadableStream<Uint8Array> | null,
  limit: number,
  timeoutMs = 3000,
): Promise<Uint8Array> {
  if (!stream) throw new BodyError(400);
  const reader = stream.getReader();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new BodyError(503)), timeoutMs);
  });
  try {
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await Promise.race([reader.read(), deadline]);
      if (done) break;
      size += value.length;
      if (size > limit) throw new BodyError(413);
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    return bytes;
  } catch (error) {
    // Do not let an unresponsive stream's cancel delay the bounded response.
    void reader.cancel().catch(() => {});
    throw error;
  } finally {
    clearTimeout(timer);
    reader.releaseLock();
  }
}

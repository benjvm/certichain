/* Local-only viewer. The export hook samples this exact lottie-web SVG. */
"use strict";
window.branding = { ready: false, errors: [] };

(async () => {
  const status = document.getElementById("status");
  try {
    if (!window.lottie)
      throw new Error("Falta lottie-web: ejecuta npm ci en tools/branding.");
    const response = await fetch(
      "../../mobile/assets/animations/certichain_intro.json",
    );
    if (!response.ok)
      throw new Error(`No se pudo leer el JSON (${response.status}).`);
    const data = await response.json();
    const player = document.getElementById("animation");
    const reducedMotion = matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const animation = lottie.loadAnimation({
      container: player,
      renderer: "svg",
      loop: false,
      autoplay: false,
      animationData: data,
      rendererSettings: { progressiveLoad: false },
    });
    animation.addEventListener("data_failed", () =>
      window.branding.errors.push("data_failed"),
    );
    animation.addEventListener("error", () =>
      window.branding.errors.push("renderer error"),
    );
    await new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error("El reproductor no terminó de cargar.")),
        10000,
      );
      animation.addEventListener("DOMLoaded", () => {
        clearTimeout(timer);
        resolve();
      });
    });
    animation.setSubframe(false);
    const end = Math.ceil(data.op - data.ip) - 1;
    const slider = document.getElementById("frame");
    slider.max = end;
    const play = document.getElementById("play");
    const update = () => {
      slider.value = Math.floor(animation.currentFrame);
      document.getElementById("time").value =
        `${(animation.currentFrame / data.fr).toFixed(2)} / ${(end / data.fr + 1 / data.fr).toFixed(2)} s`;
      play.textContent = animation.isPaused ? "Play" : "Pause";
    };
    const seek = (frame) => {
      animation.goToAndStop(Math.max(0, Math.min(frame, end)), true);
      update();
    };
    play.onclick = () => {
      if (animation.isPaused) {
        if (animation.currentFrame >= end) animation.goToAndPlay(0, true);
        else animation.play();
      } else animation.pause();
      update();
    };
    document.getElementById("restart").onclick = () => {
      animation.goToAndPlay(0, true);
      update();
    };
    slider.oninput = () => seek(Number(slider.value));
    document.getElementById("background").onchange = (event) => {
      document.getElementById("stage").className =
        `stage ${event.target.value}`;
      status.textContent =
        event.target.value === "light"
          ? "El blanco de «Certi» pertenece a la marca; utiliza un fondo oscuro para conservar el contraste."
          : "Recurso local · sin imágenes ni fuentes externas";
    };
    document.getElementById("size").onchange = (event) => {
      player.style.width = `${event.target.value}px`;
      animation.resize();
    };
    document.getElementById("loop").onchange = (event) => {
      animation.loop = event.target.checked;
    };
    animation.addEventListener("enterFrame", update);
    animation.addEventListener("complete", () => {
      seek(end);
    });

    const rasterize = async (svg, size, background) => {
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = size;
      const context = canvas.getContext("2d");
      if (background) {
        context.fillStyle = background;
        context.fillRect(0, 0, size, size);
      }
      const url = URL.createObjectURL(
        new Blob([svg], { type: "image/svg+xml" }),
      );
      try {
        const image = new Image();
        image.src = url;
        await image.decode();
        context.drawImage(image, 0, 0, size, size);
        return canvas.toDataURL("image/png");
      } finally {
        URL.revokeObjectURL(url);
      }
    };
    const snapshot = async (frame, size = 600, background = "#080B1C") => {
      seek(frame);
      const svg = player.querySelector("svg").cloneNode(true);
      svg.setAttribute("width", size);
      svg.setAttribute("height", size);
      return rasterize(
        new XMLSerializer().serializeToString(svg),
        size,
        background,
      );
    };
    Object.assign(window.branding, {
      animation,
      seek,
      snapshot,
      rasterize,
      data,
      ready: true,
    });
    status.textContent = reducedMotion
      ? "Muestra estática por tu preferencia de movimiento reducido. Play reproduce la intro."
      : "Recurso local · sin imágenes ni fuentes externas";
    if (reducedMotion) seek(end);
    else animation.play();
    update();
  } catch (error) {
    status.textContent = `No se pudo cargar la vista previa. ${error.message} Abre esta página mediante el servidor local documentado.`;
    window.branding.errors.push(error.message);
  }
})();

$ErrorActionPreference = 'Stop'
$fixtureDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../fixtures'))
$vector = Get-Content -Raw -LiteralPath (Join-Path $fixtureDirectory 'protocol-v1.json') | ConvertFrom-Json
function Decode-Hex([string] $value) {
    return ,([Convert]::FromHexString($value.Substring(2)))
}
function Digest([byte[]] $value) {
    return '0x' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($value)).ToLowerInvariant()
}
$pdf = [IO.File]::ReadAllBytes((Join-Path $fixtureDirectory 'synthetic.pdf'))
$uuidBytes = Decode-Hex ('0x' + $vector.credential_code.Replace('-', '').ToLowerInvariant())
$keyPreimage = [Text.Encoding]::UTF8.GetBytes("certichain:certificate-key:v1`0") + $uuidBytes
$commitmentPreimage = [Text.Encoding]::UTF8.GetBytes("certichain:document-commitment:v1`0") + (Decode-Hex $vector.certificate_key) + (Decode-Hex $vector.issuer_id) + (Decode-Hex $vector.document_sha256) + (Decode-Hex $vector.salt)
if ($pdf.Length -ne 330 -or $keyPreimage.Length -ne 46 -or $commitmentPreimage.Length -ne 162) { throw 'Invalid vector lengths' }
if ((Digest $pdf) -cne $vector.document_sha256) { throw 'H mismatch' }
if ((Digest $keyPreimage) -cne $vector.certificate_key) { throw 'K mismatch' }
if ((Digest $commitmentPreimage) -cne $vector.commitment) { throw 'C mismatch' }
Write-Output '9A synthetic vector verified independently with .NET SHA256'

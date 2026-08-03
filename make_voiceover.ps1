# Regenerates the pitch voiceover from pitch_narration.txt using edge-tts.
#
#   .\make_voiceover.ps1                      # default: Andrew, normal speed
#   .\make_voiceover.ps1 -Voice en-US-AriaNeural
#   .\make_voiceover.ps1 -Rate "-10%"         # slower / more deliberate
#
# Browse voices:  python -m edge_tts --list-voices
# Good narrators: en-US-AndrewNeural (warm, confident)  en-US-AriaNeural (positive)
#                 en-US-JennyNeural (friendly)          en-US-ChristopherNeural (authority)
param(
    [string]$Voice = "en-US-AndrewNeural",
    [string]$Rate  = "+0%",
    [string]$Out   = "pitch_voiceover.mp3"
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

python -m edge_tts --voice $Voice --rate $Rate `
    --file pitch_narration.txt --write-media $Out

if (Test-Path $Out) {
    $f = Get-Item $Out
    Write-Host ""
    Write-Host "Done: $Out ($([math]::Round($f.Length/1KB,1)) KB) — voice: $Voice, rate: $Rate" -ForegroundColor Green
} else {
    Write-Host "Failed — check your internet connection (edge-tts is a free online service)." -ForegroundColor Red
}

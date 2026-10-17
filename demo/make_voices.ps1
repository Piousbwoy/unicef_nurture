param(
    [Parameter(Mandatory=$true)][string]$LinesFile,
    [Parameter(Mandatory=$true)][string]$OutDir
)
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.SelectVoice("Microsoft David Desktop")
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$lines = Get-Content -Path $LinesFile -Encoding UTF8
for ($i = 0; $i -lt $lines.Count; $i++) {
    $text = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    $out = Join-Path $OutDir ("beat_{0:d2}.wav" -f ($i + 1))
    $synth.SetOutputToWaveFile($out, $fmt)
    $synth.Speak($text)
    $synth.SetOutputToNull()
    Write-Output ("{0} -> {1}" -f $out, $text.Substring(0, [Math]::Min(60, $text.Length)))
}
$synth.Dispose()

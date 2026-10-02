param(
  [int]$Min = 85,
  [int]$Max = 85
)
$ErrorActionPreference = "Stop"
$ua = "Mozilla/5.0"

if (-not $env:SUPABASE_URL -or -not $env:SUPABASE_SECRET_KEY) {
  throw "Faltam os secrets SUPABASE_URL / SUPABASE_SECRET_KEY"
}
$base = $env:SUPABASE_URL.TrimEnd("/")
$key  = $env:SUPABASE_SECRET_KEY
$headers = @{ apikey = $key; Prefer = "resolution=merge-duplicates,return=minimal" }
if ($key.StartsWith("eyJ")) { $headers["Authorization"] = "Bearer $key" }

$pos = @{
  0="GK";1="SW";2="RWB";3="RB";4="RCB";5="CB";6="LCB";7="LB";8="LWB";
  9="RDM";10="CDM";11="LDM";12="RM";13="RCM";14="CM";15="LCM";16="LM";
  17="RAM";18="CAM";19="LAM";20="RF";21="CF";22="LF";23="RW";24="RS";
  25="ST";26="LS";27="LW"
}

$agora  = (Get-Date).ToUniversalTime().ToString("o")
$cartas = @{}

foreach ($r in $Min..$Max) {
  $antes = $cartas.Count
  $page  = 1
  do {
    $uri = "https://www.fut.gg/api/fut/players/v2/27/?page=$page&overall__gte=$r&overall__lte=$r"
    $j = Invoke-RestMethod $uri -UserAgent $ua -Headers @{ Accept = "application/json" }
    foreach ($p in $j.data) {
      $posId = if ($null -ne $p.positionId) { $p.positionId } else { $p.position }
      $cartas["$($p.eaId)"] = [ordered]@{
        ea_id         = [int64]$p.eaId
        nome          = if ($p.commonName) { $p.commonName } else { "$($p.firstName) $($p.lastName)".Trim() }
        overall       = [int]$p.overall
        posicao       = if ($null -ne $posId) { $pos[[int]$posId] } else { $null }
        posicoes_alt  = @(@($p.alternativePositionIds) | Where-Object { $null -ne $_ } | ForEach-Object { $pos[[int]$_] })
        clube         = $p.club.name
        liga          = $p.league.name
        nacao         = $p.nation.name
        raridade      = $p.rarity.name
        atualizado_em = $agora
      }
    }
    $page++
    Start-Sleep -Milliseconds 700
  } while ($j.next -and @($j.data).Count -gt 0 -and $page -le 200)
  "rating $r : $($cartas.Count - $antes) cartas lidas (FUT.GG diz total=$($j.total))"
}

$lista = @($cartas.Values)
if ($lista.Count -eq 0) { throw "Nenhuma carta lida - nada a gravar" }

for ($i = 0; $i -lt $lista.Count; $i += 300) {
  $lote = $lista[$i..([Math]::Min($i + 299, $lista.Count - 1))]
  $json = $lote | ConvertTo-Json -Depth 5 -AsArray
  Invoke-RestMethod -Method Post -Uri "$base/rest/v1/cartas?on_conflict=ea_id" `
    -Headers $headers -ContentType "application/json; charset=utf-8" -Body $json | Out-Null
}
"Gravadas/atualizadas: $($lista.Count) cartas"

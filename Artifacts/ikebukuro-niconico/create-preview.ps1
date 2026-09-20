$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/../../Tools/Automation/MapRakuPipe.psm1"
Set-MapRakuEndpoint 'MapRaku.Plugin.14976.{AD540E6D-B6A5-45FC-8D4B-3B4E8CB6F673}'
function Color($hex) { $r=[Convert]::ToInt32($hex.Substring(0,2),16); $g=[Convert]::ToInt32($hex.Substring(2,2),16); $b=[Convert]::ToInt32($hex.Substring(4,2),16); return $r+256*$g+65536*$b }
$ink=Color '263845'; $road=Color 'C5CDD1'; $red=Color 'E74942'; $paper=Color 'FAF8F2'
$ops=[Collections.Generic.List[object]]::new()
function Add($s) { $ops.Add(@{op='add';spec=$s}) }
function Road($id,$name,$width,$pts,$color=$road) { Add @{kind='road';id=$id;name=$name;width=$width;color=$color;line_cap=0;vertices=@($pts|ForEach-Object {@{x=$_[0];y=$_[1]}})} }
function Label($id,$text,$x,$y,$w,$h,$size,$color=$ink) { Add @{kind='text';id=$id;name=$text;text=$text;x=[double]$x;y=[double]$y;width=[double]$w;height=[double]$h;font='Yu Gothic UI';font_size=$size;color=$color} }
function Building($id,$name,$x,$y,$w,$h,$color,$size=30,$tc=$ink) { Add @{kind='building';id=$id;name=$name;label=$name;x=[double]$x;y=[double]$y;width=[double]$w;height=[double]$h;color=$color;text_color=$tc;font_size=$size} }
$doc=Invoke-MapRakuPipe @{command='get_document'}
if ($doc.snapshot.document.layers.Count -ne 0) { throw 'Expected empty map; existing content must be reviewed.' }
$doc|ConvertTo-Json -Depth 100|Set-Content "$PSScriptRoot/before.json" -Encoding utf8
$ops.Add(@{op='canvas';spec=@{width=1920;height=1080;background=$paper;transparent=$false;jr_primary=$ink;jr_secondary=$paper}})
# Simplified east-side street layout, south left / north right, east down.
Road 'meiji' '明治通り' 44 @(@(55,325),@(395,325),@(630,270),@(885,445))
Road 'parco-front' 'PARCO本館前・P＇PARCOへの道' 30 @(@(630,270),@(615,125),@(555,65),@(555,-85))
Road 'pparco-front' 'P＇PARCO前の道路' 30 @(@(615,125),@(790,65),@(840,85),@(915,85))
# We Road is a pedestrian passage, visually separate from the main road.
Road 'we-road' 'ウイロード（歩行者通路）' 18 @(@(555,-85),@(555,-290)) (Color '90ADA9')
Add @{kind='jr';id='jr-ikebukuro';name='JR線（模式）';width=22;line_cap=0;vertices=@(@{x=40;y=-220},@{x=915;y=-220})}
Building 'station' '池袋駅' 275 -220 390 96 $ink 49 (Color 'FFFFFF')
Building 'parco-main' 'PARCO 本館' 340 150 350 100 (Color 'DCE5E3') 33
Building 'pparco' 'P＇PARCO' 745 -25 270 110 $red 39 (Color 'FFFFFF')
# Destination callout remains above the streets and has its own editable objects.
Label 'destination-name' 'ニコニコ本社' 595 -370 335 70 47 $red
Label 'destination-detail' '旧・池袋アンテナショップ' 575 -302 355 46 24
Label 'destination-floor' 'B1F・B2F' 658 -130 210 40 27 $red
Label 'east-exit' '東口' 110 -95 150 55 33
Label 'we-road-label' 'ウイロード' 382 -150 175 40 23 (Color '517975')
Label 'meiji-label' '明治通り' 100 366 205 48 29
Label 'jr-label' 'JR線' 100 -305 160 45 29
Label 'north-label' '北 →' 777 -465 135 50 29
Label 'map-note' '位置関係を簡略化した案内図・縮尺は一定ではありません' 70 462 845 38 20 (Color '677579')
$request=Get-MapRakuTokens
$request.command='preview_batch'; $request.operations=@($ops.ToArray())
$request|ConvertTo-Json -Depth 100|Set-Content "$PSScriptRoot/preview-request.json" -Encoding utf8
$preview=Invoke-MapRakuPipe $request
$candidate=$preview.candidate.document
# Empty editor retained old crossing references; the new independent map has none.
$candidate.crossingRelations=@(@{objectAId='we-road';objectBId='jr-ikebukuro';kind=4;upperObjectId='jr-ikebukuro';rangeMargin=5.0})
$candidate=($candidate|ConvertTo-Json -Depth 100).Replace([char]0xFF07,[char]0x2019)|ConvertFrom-Json -Depth 100
$candidate|ConvertTo-Json -Depth 100|Set-Content "$PSScriptRoot/candidate.json" -Encoding utf8
$null=Invoke-MapRakuPipe @{command='validate_document';document=$candidate}
$renderRequest=Get-MapRakuTokens
$renderRequest.command='render_preview'; $renderRequest.document=$candidate
$renderRequest.max_edge=1920; $renderRequest.include_reference=$false
$render=(Invoke-MapRakuPipe $renderRequest).snapshot
$png=Receive-MapRakuBlob $render.images.composite_image
[IO.File]::WriteAllBytes("$PSScriptRoot/preview.png",$png)
$null=Receive-MapRakuBlob $render.images.base_image
$null=Receive-MapRakuBlob $render.images.overlay_image
$request|ConvertTo-Json -Depth 100|Set-Content "$PSScriptRoot/preview-request.json" -Encoding utf8
Write-Output "Preview: $PSScriptRoot/preview.png; layers=$($candidate.layers.Count)"

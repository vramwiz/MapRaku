# 架空の案内図を共通の配置仕様だけで組み立て、実在施設の推測を混ぜず通信・編集を検証する。
function New-MapRakuSampleReference {
    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Bitmap]::new(1000,720)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $road = [Drawing.Pen]::new([Drawing.Color]::LightGray,30)
    $rail = [Drawing.Pen]::new([Drawing.Color]::Black,8)
    $river = [Drawing.Pen]::new([Drawing.Color]::LightBlue,40)
    $font = [Drawing.Font]::new('Yu Gothic UI',18)
    $stream = [IO.MemoryStream]::new()
    try {
        $graphics.Clear([Drawing.Color]::White)
        $graphics.DrawLine($road,60,410,940,410)
        $graphics.DrawLine($road,380,70,380,630)
        $graphics.DrawLine($rail,60,210,940,210)
        $graphics.DrawLine($rail,160,80,160,640)
        $graphics.DrawBezier($river,785,70,745,240,770,480,840,650)
        $graphics.DrawString('中央駅',[Drawing.Font]$font,[Drawing.Brushes]::Black,500,170)
        $graphics.DrawString('北 ↑',[Drawing.Font]$font,[Drawing.Brushes]::Black,890,20)
        $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    } finally {
        $stream.Dispose(); $font.Dispose(); $river.Dispose(); $rail.Dispose()
        $road.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
    }
}

function Get-MapRakuSampleOperations {
    $items = [Collections.Generic.List[object]]::new()
    $items.Add(@{op='canvas'; spec=@{width=1000; height=720; background=16777215}})
    $paths = @(
        @{kind='road'; id='main-road'; name='駅前通り'; width=30; vertices=@(@{x=-440;y=50},@{x=440;y=50})},
        @{kind='road'; id='north-road'; name='中央通り'; width=24; vertices=@(@{x=-120;y=-290},@{x=-120;y=270})},
        @{kind='road'; id='curve-road'; name='公園通り'; width=20; vertices=@(
            @{x=-120;y=170;kind='bezier';outgoingSegment='cubicBezier';outgoingX=120;outgoingY=0},
            @{x=200;y=260;kind='bezier';incomingX=-110;incomingY=0})},
        @{kind='jr'; id='jr'; name='JR線'; width=14; vertices=@(@{x=-440;y=-150},@{x=440;y=-150})},
        @{kind='rail'; id='rail'; name='私鉄'; width=10; vertices=@(@{x=-340;y=-280},@{x=-340;y=280})},
        @{kind='river'; id='river'; name='青葉川'; width=40; vertices=@(
            @{x=285;y=-290;kind='bezier';outgoingSegment='cubicBezier';outgoingX=-40;outgoingY=170},
            @{x=340;y=290;kind='bezier';incomingX=-70;incomingY=-170})}
    )
    foreach ($p in $paths) { $items.Add(@{op='add';spec=$p}) }
    $items.Add(@{op='crossing';a='main-road';b='river';kind=3;upper='main-road';margin=18})
    $items.Add(@{op='crossing';a='north-road';b='jr';kind=4;upper='jr';margin=18})
    $items.Add(@{op='crossing';a='main-road';b='rail';kind=1})
    $items.Add(@{op='crossing';a='jr';b='river';kind=3;upper='jr';margin=18})
    $items.Add(@{op='crossing';a='jr';b='rail';kind=4;upper='jr';margin=18})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=0;id='station';label='中央駅';x=50;y=-150}})
    $items.Add(@{op='add';spec=@{kind='building';id='hall';name='市役所';x=70;y=-20;width=110;height=70}})
    $items.Add(@{op='add';spec=@{kind='building';id='museum';name='美術館';x=80;y=135;width=110;height=65}})
    $items.Add(@{op='add';spec=@{kind='ellipse';id='park';name='中央公園';x=-290;y=100;width=100;height=110;color=12184020}})
    $items.Add(@{op='add';spec=@{kind='text';id='park-label';text='中央公園';x=-284;y=137;width=100;height=30;font_size=18}})
    $items.Add(@{op='add';spec=@{kind='text';id='title';text='中央駅周辺 案内図';x=-435;y=-335;width=450;height=40;font_size=26}})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=5;id='parking';x=195;y=-30}})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=6;id='north';x=430;y=-275}})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=1;id='signal';x=-95;y=20}})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=2;id='crosswalk';x=-160;y=50;rotation=90}})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=3;id='footbridge';x=190;y=50;rotation=90}})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=4;id='marker';label='1';x=80;y=220}})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=7;id='route';label='12';x=-230;y=50}})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=8;id='pond';x=-235;y=240}})
    $items.Add(@{op='add';spec=@{kind='symbol';symbol=9;id='arrow';x=0;y=285}})
    return $items.ToArray()
}

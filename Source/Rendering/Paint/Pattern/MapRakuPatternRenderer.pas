// 内蔵模様を必要解像度のタイルへ展開し、描画呼び出し内で共有する。
unit MapRakuPatternRenderer;

interface

uses System.Skia, System.Types, MapRakuPatternStyle;

// 戻り値を保持している間だけキャッシュを共有する。解放時に全Skia画像を破棄する。
function BeginMapRakuPatternRender(Scale: Single): IInterface;
// UIのプレビューにも使用するタイル生成。論理周期をTileSizeへ返す。
function MakeMapRakuPatternTile(const Style: TMapRakuPatternStyle;
  Scale: Single; out TileSize: TSizeF): ISkImage;
// オブジェクト中心を基準に回転・移動する繰り返し模様をPaintへ反映する。
procedure ApplyMapRakuPattern(const Paint: ISkPaint; const Style: TMapRakuPatternStyle;
  const Bounds: TRectF; Rotation, Opacity: Single);

implementation

uses System.Math, System.Math.Vectors, System.UITypes, System.Generics.Collections,
  Vcl.Graphics, Winapi.Windows;

type
  TPatternTile = class
    Style: TMapRakuPatternStyle; // キャッシュ照合用の不変スナップショット。
    Image: ISkImage;                  // この描画スコープだけが所有する展開画像。
    Size: TSizeF;                     // 画像解像度とは独立した論理周期。
  end;
  TPatternRenderScope = class(TInterfacedObject)
  private
    FPrevious: TPatternRenderScope;        // 入れ子描画の復帰先。
    FScale: Single;                       // 解像度選択の倍率。
    FTiles: TObjectList<TPatternTile>;    // 最大8画像、最大32 MiBの展開画像。
  public
    constructor Create(Scale: Single);
    destructor Destroy; override;
    function Tile(const Style: TMapRakuPatternStyle): TPatternTile;
  end;

threadvar
  CurrentScope: TPatternRenderScope; // UIとプラグイン描画をスレッド間で共有しない。

function AlphaColor(const Slot: TMapRakuPatternColor): TAlphaColor;
var C: Cardinal;
begin
  C := ColorToRGB(Slot.Color);
  Result := (Cardinal(Round(Slot.Opacity * 255)) shl 24) or
    (Cardinal(GetRValue(C)) shl 16) or (Cardinal(GetGValue(C)) shl 8) or GetBValue(C);
end;

function PatternSize(const Style: TMapRakuPatternStyle): TSizeF;
var R: Single;
begin
  case Style.Kind of
    slptHatch, slptDots: Result := TSizeF.Create(Style.Number('spacing'), Style.Number('spacing'));
    slptGrid: Result := TSizeF.Create(Style.Number('spacingX'), Style.Number('spacingY'));
    slptChecker: Result := TSizeF.Create(2 * Style.Number('size'), 2 * Style.Number('size'));
    slptWave: Result := TSizeF.Create(Style.Number('period'), Style.Number('spacing'));
  else
    R := Style.Number('size') + Style.Number('spacing') / 2;
    Result := TSizeF.Create(3 * R, Sqrt(3) * R);
  end;
end;

function MakeMapRakuPatternTile(const Style: TMapRakuPatternStyle;
  Scale: Single; out TileSize: TSizeF): ISkImage;
var
  Surface: ISkSurface;
  Paint: ISkPaint;
  Path: ISkPathBuilder;
  W, H, X, Y, I, J, Steps, Rows, ExtraSteps: Integer;
  A, R, Pitch, CX, CY, PX, PY, LW: Single;
begin
  TileSize := PatternSize(Style);
  // 1/4オクターブで切り上げ、低倍率は最低8px、巨大周期は一辺1024pxへ制限する。
  Scale := Power(2, Ceil(Log2(Max(Scale, 0.01)) * 4) / 4);
  W := EnsureRange(Ceil(TileSize.Width * Scale), 8, 1024);
  H := EnsureRange(Ceil(TileSize.Height * Scale), 8, 1024);
  Surface := TSkSurface.MakeRaster(W, H);
  Surface.Canvas.Clear(AlphaColor(Style.Slot('background')));
  Surface.Canvas.Scale(W / TileSize.Width, H / TileSize.Height);
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := AlphaColor(Style.Slot('foreground'));
  Path := TSkPathBuilder.Create;
  LW := 1;
  if Style.Kind in [slptHatch, slptGrid, slptWave, slptHoneycomb] then
    LW := Min(Style.Number('width'), Min(TileSize.Width, TileSize.Height));
  Paint.StrokeWidth := LW;
  Paint.Style := TSkPaintStyle.Stroke;
  case Style.Kind of
    slptHatch:
      for Y := 0 to 1 do
      begin
        Path.MoveTo(-LW, Y * TileSize.Height);
        Path.LineTo(TileSize.Width + LW, Y * TileSize.Height);
      end;
    slptGrid:
      for I := 0 to 1 do
      begin
        Path.MoveTo(-LW, I * TileSize.Height);
        Path.LineTo(TileSize.Width + LW, I * TileSize.Height);
        Path.MoveTo(I * TileSize.Width, -LW);
        Path.LineTo(I * TileSize.Width, TileSize.Height + LW);
      end;
    slptDots:
      begin
        Paint.Style := TSkPaintStyle.Fill;
        R := Min(Style.Number('size'), TileSize.Width) / 2;
        Path.AddCircle(TileSize.Width / 2, TileSize.Height / 2, R);
      end;
    slptChecker:
      begin
        Paint.Style := TSkPaintStyle.Fill;
        R := Style.Number('size');
        Path.AddRect(TRectF.Create(0, 0, R, R));
        Path.AddRect(TRectF.Create(R, R, 2 * R, 2 * R));
      end;
    slptWave:
      begin
        A := Style.Number('amplitude');
        Steps := EnsureRange(W * 2, 64, 2048);
        ExtraSteps := Ceil(LW * Steps / TileSize.Width) + 1;
        Rows := Ceil((A + LW) / TileSize.Height) + 1;
        for Y := -Rows to Rows do
        begin
          // 両端の外側まで同じ正弦曲線を描き、周期境界の端点を露出させない。
          for I := -ExtraSteps to Steps + ExtraSteps do
          begin
            PX := TileSize.Width * I / Steps;
            PY := Y * TileSize.Height + A * Sin(2 * Pi * I / Steps);
            if I = -ExtraSteps then Path.MoveTo(PX, PY) else Path.LineTo(PX, PY);
          end;
        end;
      end;
    slptHoneycomb:
      begin
        R := Style.Number('size');
        Pitch := R + Style.Number('spacing') / 2;
        Paint.StrokeWidth := Min(LW, R);
        for X := -1 to 1 do
          for Y := -1 to 1 do
            for J := 0 to 1 do
            begin
              CX := (X * 3 + J * 1.5) * Pitch;
              CY := (Y + J * 0.5) * Sqrt(3) * Pitch;
              for I := 0 to 5 do
              begin
                PX := CX + R * Cos(I * Pi / 3);
                PY := CY + R * Sin(I * Pi / 3);
                if I = 0 then Path.MoveTo(PX, PY) else Path.LineTo(PX, PY);
              end;
              Path.Close;
            end;
      end;
  end;
  Surface.Canvas.DrawPath(Path.Detach, Paint);
  Result := Surface.MakeImageSnapshot;
end;

constructor TPatternRenderScope.Create(Scale: Single);
begin
  inherited Create;
  FScale := Scale;
  FTiles := TObjectList<TPatternTile>.Create(True);
  FPrevious := CurrentScope;
  CurrentScope := Self;
end;

destructor TPatternRenderScope.Destroy;
begin
  CurrentScope := FPrevious;
  FTiles.Free;
  inherited;
end;

function TPatternRenderScope.Tile(const Style: TMapRakuPatternStyle): TPatternTile;
var Item: TPatternTile;
begin
  for Item in FTiles do if Item.Style.SameAs(Style) then Exit(Item);
  if FTiles.Count >= 8 then FTiles.Delete(0);
  Result := TPatternTile.Create;
  try
    Result.Style := Style;
    Result.Image := MakeMapRakuPatternTile(Style, FScale, Result.Size);
    FTiles.Add(Result);
  except
    Result.Free;
    raise;
  end;
end;

function BeginMapRakuPatternRender(Scale: Single): IInterface;
begin
  Result := TPatternRenderScope.Create(Scale);
end;

procedure ApplyMapRakuPattern(const Paint: ISkPaint; const Style: TMapRakuPatternStyle;
  const Bounds: TRectF; Rotation, Opacity: Single);
var
  FlipX, FlipY: Single;
  Image: ISkImage;
  Size: TSizeF;
  Tile: TPatternTile;
  Matrix: TMatrix;
begin
  if CurrentScope <> nil then
  begin
    Tile := CurrentScope.Tile(Style);
    Image := Tile.Image;
    Size := Tile.Size;
  end
  else Image := MakeMapRakuPatternTile(Style, 1, Size);
  if Style.FlipHorizontal then FlipX := -1 else FlipX := 1;
  if Style.FlipVertical then FlipY := -1 else FlipY := 1;
  Matrix := TMatrix.CreateScaling(Size.Width / Image.Width, Size.Height / Image.Height) *
    TMatrix.CreateRotation(DegToRad(Style.Number('angle'))) *
    TMatrix.CreateTranslation(Style.Number('offsetX'), Style.Number('offsetY')) *
    TMatrix.CreateScaling(FlipX, FlipY) *
    TMatrix.CreateRotation(DegToRad(Rotation)) *
    TMatrix.CreateTranslation(Bounds.CenterPoint.X, Bounds.CenterPoint.Y);
  Paint.Shader := Image.MakeShader(Matrix, TSkSamplingOptions.Create(TSkFilterMode.Linear, TSkMipmapMode.None),
    TSkTileMode.Repeat, TSkTileMode.Repeat);
  Paint.Color := TAlphaColor((Cardinal(EnsureRange(Round(Opacity * 255), 0, 255)) shl 24) or $FFFFFF);
end;

end.

// テクスチャの中心移動と拡縮・回転を直接操作し、ドラッグを1件のUndoへまとめる。
unit MapRakuTextureInteraction;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Graphics, Vcl.Direct2D,
  MapRakuDocument, MapRakuEditorState, MapRakuEditHistory, MapRakuPaintStyles;

type
  TMapRakuTextureInteraction = class
  private
    FDocument: TVectArtDocument;             // 操作対象のDocument。
    FState: TVectArtEditorState;              // 選択階層とツール状態。
    FHistory: TVectArtEditHistory;            // 確定操作のUndo先。
    FBounds: TRect;                          // キャンバス表示領域。
    FZoom: Single;                           // 論理座標から画面への倍率。
    FLayer: TVectArtLayer;                   // ドラッグ中だけ保持する対象。
    FOld: TMapRakuPaintStyle;           // 操作前の画像と配置。
    FStart: TPoint;                          // ドラッグ開始位置。
    FCenter: TPoint;                         // 操作開始時の画像中心。
    FHandle: Integer;                        // 0は未操作、1は中心、2は拡縮・回転。
    function ActiveLayer: TVectArtLayer;
    function ToScreen(const P: TPointF): TPoint;
  public
    // 表示座標と操作先を設定する。
    procedure Configure(Document: TVectArtDocument; History: TVectArtEditHistory;
      State: TVectArtEditorState; const Bounds: TRect; Zoom: Single);
    // 単一選択画像の中心と右端ハンドルを画面座標で返す。
    function GuidePoints(out Center, Edge: TPoint): Boolean;
    // ガイドの中心または右端が押された場合だけ入力を取得する。
    function MouseDown(Button: TMouseButton; X, Y: Integer): Boolean;
    // 中心は移動、右端は拡縮・回転。Shiftでは角度を15度に揃える。
    function MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
    // 操作を終了し、変更があった場合だけ履歴へ追加する。
    function MouseUp(X, Y: Integer): Boolean;
    // 白黒の線と異なる形のハンドルをGDI／Direct2Dへ描く。
    procedure Draw(Target: TCanvas); overload;
    procedure Draw(Target: TDirect2DCanvas); overload;
    destructor Destroy; override;
  end;

implementation

uses
  System.Math, System.Math.Vectors, System.Skia, MapRakuGeometry,
  MapRakuLayerGeometry, MapRakuTextureRenderer, MapRakuTextureStyle,
  MapRakuPaintCommands, MapRakuOverlayPrimitives, MapRakuOverlayHandles;

procedure TMapRakuTextureInteraction.Configure(Document: TVectArtDocument; History: TVectArtEditHistory;
  State: TVectArtEditorState; const Bounds: TRect; Zoom: Single);
begin
  FDocument := Document;
  FHistory := History;
  FState := State;
  FBounds := Bounds;
  FZoom := Zoom;
end;

destructor TMapRakuTextureInteraction.Destroy;
begin
  if (FHandle <> 0) and (FDocument <> nil) then FDocument.EndInteractiveUpdate;
  inherited;
end;

function TMapRakuTextureInteraction.ActiveLayer: TVectArtLayer;
var
  Selected: TArray<Integer>;
  Children: TArray<TVectArtLayer>;
begin
  Result := nil;
  if (FDocument = nil) or (FDocument.CanvasLayer = nil) or (FState = nil) or
    (FState.CurrentTool <> vetSelect) or (FState.SelectedFilter <> nil) then Exit;
  if FState.OpenGroup <> nil then
  begin
    Children := FState.GetOpenGroupChildren;
    if Length(Children) = 1 then Result := Children[0];
  end
  else
  begin
    Selected := FDocument.GetSelectedLayerIndices;
    if (Length(Selected) = 1) and (Selected[0] > 0) then Result := FDocument[Selected[0]];
  end;
  if (Result <> nil) and (Result.Locked or (Result.PaintStyle.Kind <> slpkTexture) or
    (Result.PaintStyle.Texture.Data = '')) then Result := nil;
end;

function TMapRakuTextureInteraction.ToScreen(const P: TPointF): TPoint;
begin
  Result := Point(LogicalToScreenX(P.X, FBounds, FZoom, FDocument.CanvasLayer.Width),
    LogicalToScreenY(P.Y, FBounds, FZoom, FDocument.CanvasLayer.Height));
end;

function TMapRakuTextureInteraction.GuidePoints(out Center, Edge: TPoint): Boolean;
var
  Layer: TVectArtLayer;
  Bounds: TRectF;
  Rotation: Single;
  Img: ISkImage;
  Matrix: TMatrix;
begin
  Result := False;
  Layer := ActiveLayer;
  if Layer = nil then Exit;
  if not TryGetMapRakuLayerPaintGeometry(Layer, Bounds, Rotation) then Exit;
  Img := DecodeMapRakuTexture(Layer.PaintStyle.Texture.Data);
  if Img = nil then Exit;
  Matrix := MapRakuTextureMatrix(Layer.PaintStyle.Texture, Bounds, Img.Width, Img.Height, Rotation);
  Center := ToScreen(TPointF.Create(Img.Width / 2, Img.Height / 2) * Matrix);
  Edge := ToScreen(TPointF.Create(Img.Width, Img.Height / 2) * Matrix);
  Result := True;
end;

function TMapRakuTextureInteraction.MouseDown(Button: TMouseButton; X, Y: Integer): Boolean;
var
  C, E: TPoint;
begin
  Result := False;
  if (Button <> mbLeft) or not GuidePoints(C, E) then Exit;
  if Hypot(X-C.X, Y-C.Y) <= 9 then FHandle := 1
  else if Hypot(X-E.X, Y-E.Y) <= 9 then FHandle := 2
  else Exit;
  FLayer := ActiveLayer;
  FOld := FLayer.PaintStyle;
  FStart := Point(X, Y);
  FCenter := C;
  FDocument.BeginInteractiveUpdate;
  Result := True;
end;

function TMapRakuTextureInteraction.MouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
var
  Bounds: TRectF;
  Rotation, DX, DY, Distance, StartDistance, Angle: Single;
  Style: TMapRakuPaintStyle;
  Texture: TMapRakuTextureStyle;
  C, E: TPoint;
begin
  Result := FHandle <> 0;
  if not Result then
  begin
    if (Shift = []) and GuidePoints(C, E) then
      Result := (Hypot(X-C.X, Y-C.Y) <= 9) or (Hypot(X-E.X, Y-E.Y) <= 9);
    Exit;
  end;
  if not TryGetMapRakuLayerPaintGeometry(FLayer, Bounds, Rotation) then Exit;
  Texture := FOld.Texture;
  if FHandle = 1 then
  begin
    DX := (X-FStart.X) / Max(FZoom, 0.001);
    DY := (Y-FStart.Y) / Max(FZoom, 0.001);
    Angle := DegToRad(Rotation);
    Texture.OffsetX := EnsureRange(Texture.OffsetX +
      (DX*Cos(Angle)+DY*Sin(Angle))/Max(Bounds.Width, 1), -1000.0, 1000.0);
    Texture.OffsetY := EnsureRange(Texture.OffsetY +
      (-DX*Sin(Angle)+DY*Cos(Angle))/Max(Bounds.Height, 1), -1000.0, 1000.0);
  end
  else
  begin
    Distance := Hypot(X-FCenter.X, Y-FCenter.Y);
    StartDistance := Max(Hypot(FStart.X-FCenter.X, FStart.Y-FCenter.Y), 1);
    Texture.Scale := EnsureRange(Texture.Scale * Distance / StartDistance, 0.01, 100.0);
    Angle := RadToDeg(ArcTan2(Y-FCenter.Y, X-FCenter.X) -
      ArcTan2(FStart.Y-FCenter.Y, FStart.X-FCenter.X));
    Texture.Angle := Texture.Angle + Angle;
    if ssShift in Shift then Texture.Angle := Round(Texture.Angle / 15) * 15;
    while Texture.Angle > 180 do Texture.Angle := Texture.Angle - 360;
    while Texture.Angle < -180 do Texture.Angle := Texture.Angle + 360;
  end;
  Style := FOld;
  Style.Texture := Texture;
  if not FLayer.PaintStyle.SameAs(Style) then
  begin
    FLayer.PaintStyle := Style;
    FDocument.Changed;
  end;
end;

function TMapRakuTextureInteraction.MouseUp(X, Y: Integer): Boolean;
var
  Command: TMapRakuSetLayerPaintStyleCommand;
begin
  Result := FHandle <> 0;
  if not Result then Exit;
  try
    if not FOld.SameAs(FLayer.PaintStyle) then
    begin
      Command := TMapRakuSetLayerPaintStyleCommand.Create(FDocument, FLayer, FOld, FLayer.PaintStyle);
      if FHistory <> nil then FHistory.AddApplied(Command) else Command.Free;
    end;
  finally
    FHandle := 0;
    FLayer := nil;
    FDocument.EndInteractiveUpdate;
  end;
end;

procedure TMapRakuTextureInteraction.Draw(Target: TCanvas);
var C, E: TPoint;
begin
  if not GuidePoints(C, E) then Exit;
  DrawOverlayLine(Target, C, E);
  DrawOverlayHandleEllipse(Target, Rect(C.X-6, C.Y-6, C.X+7, C.Y+7), clWhite, clBlack);
  DrawOverlayHandleRect(Target, Rect(E.X-6, E.Y-6, E.X+7, E.Y+7), clWhite, clBlack);
end;

procedure TMapRakuTextureInteraction.Draw(Target: TDirect2DCanvas);
var C, E: TPoint;
begin
  if not GuidePoints(C, E) then Exit;
  DrawOverlayLine(Target, C, E);
  DrawOverlayHandleEllipse(Target, Rect(C.X-6, C.Y-6, C.X+7, C.Y+7), clWhite, clBlack);
  DrawOverlayHandleRect(Target, Rect(E.X-6, E.Y-6, E.X+7, E.Y+7), clWhite, clBlack);
end;

end.

// テクスチャ専用のD&D領域、画像プレビューと配置設定をダークテーマで表示する。
unit MapRakuTextureControl;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Graphics, Vcl.Imaging.pngimage,
  Winapi.ActiveX, MapRakuTextureStyle;

type
  TMapRakuTextureControl = class(TCustomControl)
  private
    FTexture: TMapRakuTextureStyle; // UIが表示する埋め込み画像と配置。
    FPreview: TPngImage;                // 描画ランタイムに依存しないプレビュー。
    FOnChange: TNotifyEvent;            // 1回の確定操作を上位のUndo処理へ通知する。
    FDropTarget: IDropTarget;           // HWNDの生存期間だけ登録するOLE受け口。
    FOleInitialized: Boolean;           // このコントロールがOLE参照を取得したか。
    FHover: Boolean;                    // 専用領域で受け付け可能なドラッグ中。
    FError: string;                     // 直近の読み込み失敗。現在の画像は維持する。
    function Logical(Value: Integer): Integer;
    procedure SetTexture(const Value: TMapRakuTextureStyle);
    function DropBounds: TRect;
    procedure Changed;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    // 所有者だけで生成でき、Parent設定前にはHWNDを作らない。
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // 読み込み成功時だけ画像を置換して変更通知する。失敗はUI内に表示する。
    function LoadFile(const FileName: string): Boolean;
    property Texture: TMapRakuTextureStyle read FTexture write SetTexture;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses
  System.SysUtils, System.Math, System.Skia, Winapi.Windows, Vcl.Dialogs,
  MapRakuTextureRenderer, MapRakuTextureDropTarget;

constructor TMapRakuTextureControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreview := TPngImage.Create;
  FTexture := TMapRakuTextureStyle.DefaultStyle;
  Color := $212121;
  Font.Name := 'Segoe UI';
  Font.Height := -12;
  Font.Color := $EEEEEE;
  DoubleBuffered := True;
  Height := 238;
  ShowHint := True;
  Hint := '画像領域へ1ファイルをドロップ、またはクリックして選択';
end;

function TMapRakuTextureControl.Logical(Value: Integer): Integer;
begin
  Result := MulDiv(Value, CurrentPPI, 96);
end;

destructor TMapRakuTextureControl.Destroy;
begin
  if HandleAllocated then DestroyWindowHandle;
  FPreview.Free;
  inherited;
end;

procedure TMapRakuTextureControl.CreateWnd;
begin
  Font.Height := -Logical(12);
  inherited;
  FOleInitialized := Succeeded(OleInitialize(nil));
  FDropTarget := TMapRakuTextureDropTarget.Create(
    function(const Point: TPoint; Hover: Boolean): Boolean
    begin
      Result := Enabled and Visible and DropBounds.Contains(ScreenToClient(Point));
      FHover := Hover and Result;
      Invalidate;
    end,
    function(const FileName: string): Boolean
    begin
      Result := LoadFile(FileName);
    end);
  if not Succeeded(RegisterDragDrop(Handle, FDropTarget)) then
  begin
    FDropTarget := nil;
    FError := 'D&Dを開始できません。画像領域をクリックして選択してください';
    Hint := FError;
  end;
end;

procedure TMapRakuTextureControl.DestroyWnd;
begin
  if FDropTarget <> nil then RevokeDragDrop(Handle);
  FDropTarget := nil;
  if FOleInitialized then OleUninitialize;
  FOleInitialized := False;
  inherited;
end;

function TMapRakuTextureControl.DropBounds: TRect;
begin
  Result := Rect(0, 0, ClientWidth, Logical(82));
end;

procedure TMapRakuTextureControl.SetTexture(const Value: TMapRakuTextureStyle);
var
  Img: ISkImage;
  Surface: ISkSurface;
  PreviewImage: TPngImage;
  Ratio: Single;
  Stream: TMemoryStream;
begin
  if FTexture.Data <> Value.Data then
  begin
    Img := DecodeMapRakuTexture(Value.Data);
    PreviewImage := TPngImage.Create;
    try
      if Img <> nil then
      begin
        Ratio := Min(256 / Img.Width, 128 / Img.Height);
        Surface := TSkSurface.MakeRaster(Max(1, Round(Img.Width*Ratio)), Max(1, Round(Img.Height*Ratio)));
        Surface.Canvas.Clear(0);
        Surface.Canvas.DrawImageRect(Img,
          TRectF.Create(0, 0, Max(1, Round(Img.Width*Ratio)), Max(1, Round(Img.Height*Ratio))));
        Stream := TMemoryStream.Create;
        try
          Surface.MakeImageSnapshot.EncodeToStream(Stream);
          Stream.Position := 0;
          PreviewImage.LoadFromStream(Stream);
        finally
          Stream.Free;
        end;
      end;
      FPreview.Assign(PreviewImage);
    finally
      PreviewImage.Free;
    end;
  end;
  FTexture := Value;
  Invalidate;
end;

function TMapRakuTextureControl.LoadFile(const FileName: string): Boolean;
var
  NewTexture: TMapRakuTextureStyle;
begin
  Result := False;
  if not Enabled then Exit;
  try
    NewTexture := LoadMapRakuTexture(FileName);
    SetTexture(NewTexture);
    FError := '';
    Hint := '画像領域へ1ファイルをドロップ、またはクリックして選択';
    Changed;
    Result := True;
  except
    on E: Exception do
    begin
      FError := E.Message;
      Hint := FError;
      Invalidate;
    end;
  end;
end;

procedure TMapRakuTextureControl.Changed;
begin
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TMapRakuTextureControl.Paint;
const
  FIT_NAMES: array[TMapRakuTextureFit] of string = ('全面', '全体', '引き伸ばし', '原寸');
  REPEAT_NAMES: array[TMapRakuTextureRepeat] of string = ('なし', '通常', '鏡像');
var
  R: TRect;
  TextValue: string;
  I, TopY, RowHeight, W, H: Integer;
  Ratio: Single;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  R := DropBounds;
  Canvas.Pen.Color := $777777;
  if FHover then Canvas.Pen.Color := $FFAA55;
  Canvas.Rectangle(R);
  if not FPreview.Empty then
  begin
    Ratio := Min((R.Width - Logical(8)) / FPreview.Width,
      (R.Height - Logical(24)) / FPreview.Height);
    W := Max(1, Round(FPreview.Width * Ratio));
    H := Max(1, Round(FPreview.Height * Ratio));
    Canvas.StretchDraw(Rect((R.Width-W) div 2, Logical(3),
      (R.Width+W) div 2, H + Logical(3)), FPreview);
    TextValue := FTexture.FileName;
  end
  else
    TextValue := '画像をドロップ / 選択';
  R.Top := R.Bottom - Logical(22);
  DrawText(Canvas.Handle, PChar(TextValue), -1, R,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
  TopY := DropBounds.Bottom + Logical(4);
  RowHeight := Logical(28);
  for I := 0 to 4 do
  begin
    R := Rect(0, TopY + I * RowHeight, ClientWidth,
      TopY + (I+1) * RowHeight - Logical(2));
    Canvas.Brush.Color := $303030;
    Canvas.Pen.Color := $555555;
    Canvas.Rectangle(R);
    case I of
      0: TextValue := '配置  ' + FIT_NAMES[FTexture.Fit] + '  ›';
      1: TextValue := '繰り返し  ' + REPEAT_NAMES[FTexture.RepeatMode] + '  ›';
      2: TextValue := Format('−   拡大率 %d%%   ＋', [Round(FTexture.Scale * 100)]);
      3: TextValue := Format('−   回転 %d°   ＋', [Round(FTexture.Angle)]);
      4: TextValue := '配置リセット  |  解除';
    end;
    DrawText(Canvas.Handle, PChar(TextValue), -1, R, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  end;
  if FError <> '' then
  begin
    Canvas.Font.Color := $8080FF;
    Canvas.TextOut(Logical(2), TopY + 5 * RowHeight,
      '画像エラー（詳細はヒント）');
  end;
end;

procedure TMapRakuTextureControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Dialog: TOpenDialog;
  Row, Sign: Integer;
  Value: TMapRakuTextureStyle;
begin
  inherited;
  if (Button <> mbLeft) or not Enabled then Exit;
  if DropBounds.Contains(Point(X, Y)) then
  begin
    Dialog := TOpenDialog.Create(Self);
    try
      Dialog.Filter := '画像|*.png;*.jpg;*.jpeg;*.webp;*.bmp|すべてのファイル|*.*';
      Dialog.Options := [ofFileMustExist, ofPathMustExist, ofEnableSizing];
      if Dialog.Execute then LoadFile(Dialog.FileName);
    finally
      Dialog.Free;
    end;
    Exit;
  end;
  Row := (Y - DropBounds.Bottom - Logical(4)) div Logical(28);
  Value := FTexture;
  Sign := 1;
  if X < ClientWidth div 2 then Sign := -1;
  case Row of
    0: Value.Fit := TMapRakuTextureFit((Ord(Value.Fit) + 1) mod 4);
    1: Value.RepeatMode := TMapRakuTextureRepeat((Ord(Value.RepeatMode) + 1) mod 3);
    2: Value.Scale := EnsureRange(Value.Scale * Power(1.1, Sign), 0.01, 100.0);
    3: Value.Angle := (Round(Value.Angle) + Sign * 15) mod 360;
    4:
      if Sign > 0 then Value := TMapRakuTextureStyle.DefaultStyle
      else
      begin
        Value.Scale := 1;
        Value.OffsetX := 0;
        Value.OffsetY := 0;
        Value.Angle := 0;
      end;
    else Exit;
  end;
  if not FTexture.SameAs(Value) then
  begin
    SetTexture(Value);
    Changed;
  end;
end;

end.

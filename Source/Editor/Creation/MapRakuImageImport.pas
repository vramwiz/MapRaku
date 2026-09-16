// ドロップされた画像ファイルを検証し、画像レイヤーとして初期配置して履歴へ登録する。
unit MapRakuImageImport;

interface

uses
  System.Types, MapRakuDocument, MapRakuEditHistory;

// 読み込める画像だけをドロップ位置中心へ縦横比を保って配置し、配置数を返す。
// 読み込めなかったファイルがある場合は、成功分を維持したままErrorMessageへ理由を返す。
function ImportMapRakuImageFiles(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; const FileNames: TArray<string>;
  const DropCenter: TPointF; out ErrorMessage: string): Integer;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.Math,
  System.Skia, System.SysUtils, MapRakuLayerBatchCommands,
  MapRakuLayerNaming;

const
  IMAGE_CANVAS_FIT_RATIO = 0.8; // 大きな画像を初期配置時に用紙内へ収める比率。
  IMAGE_CASCADE_OFFSET   = 16;  // 複数画像を同時にドロップした場合のずらし量。

procedure AppendImportError(Errors: TStrings; const FileName,
  MessageText: string);
begin
  Errors.Add(ExtractFileName(FileName) + ': ' + MessageText);
end;

function BuildImageData(Document: TVectArtDocument; const FileName: string;
  const DropCenter: TPointF; CascadeIndex: Integer;
  out Data: TVectArtImageData; out ErrorMessage: string): Boolean;
var
  CanvasHeight: Single;
  CanvasWidth: Single;
  Center: TPointF;
  EncodedData: TBytes;
  HalfHeight: Single;
  HalfWidth: Single;
  Image: ISkImage;
  Scale: Single;
begin
  Result := False;
  ErrorMessage := '';
  if not TFile.Exists(FileName) then
  begin
    ErrorMessage := 'ファイルが存在しません';
    Exit;
  end;
  try
    EncodedData := TFile.ReadAllBytes(FileName);
    Image := TSkImage.MakeFromEncoded(EncodedData);
  except
    on E: Exception do
    begin
      ErrorMessage := E.Message;
      Exit;
    end;
  end;
  if (Image = nil) or (Image.Width <= 0) or (Image.Height <= 0) then
  begin
    ErrorMessage := '対応する画像ファイルではありません';
    Exit;
  end;

  CanvasWidth := Max(Document.CanvasLayer.Width, 1);
  CanvasHeight := Max(Document.CanvasLayer.Height, 1);
  Scale := Min(1.0, Min(CanvasWidth * IMAGE_CANVAS_FIT_RATIO / Image.Width,
    CanvasHeight * IMAGE_CANVAS_FIT_RATIO / Image.Height));
  HalfWidth := Image.Width * Scale * 0.5;
  HalfHeight := Image.Height * Scale * 0.5;
  Center := TPointF.Create(DropCenter.X + CascadeIndex * IMAGE_CASCADE_OFFSET,
    DropCenter.Y + CascadeIndex * IMAGE_CASCADE_OFFSET);
  Center.X := EnsureRange(Center.X, -CanvasWidth * 0.5 + HalfWidth,
    CanvasWidth * 0.5 - HalfWidth);
  Center.Y := EnsureRange(Center.Y, -CanvasHeight * 0.5 + HalfHeight,
    CanvasHeight * 0.5 - HalfHeight);

  Data := Default(TVectArtImageData);
  Data.Locked := False;
  Data.Opacity := 1.0;
  Data.PngData := EncodedData;
  Data.Points[0] := TPointF.Create(Center.X - HalfWidth,
    Center.Y - HalfHeight);
  Data.Points[1] := TPointF.Create(Center.X + HalfWidth,
    Center.Y - HalfHeight);
  Data.Points[2] := TPointF.Create(Center.X + HalfWidth,
    Center.Y + HalfHeight);
  Data.Points[3] := TPointF.Create(Center.X - HalfWidth,
    Center.Y + HalfHeight);
  Data.SourceFileName := ExpandFileName(FileName);
  Data.SourceKind := visImage;
  Data.Visible := True;
  Result := True;
end;

function ImportMapRakuImageFiles(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; const FileNames: TArray<string>;
  const DropCenter: TPointF; out ErrorMessage: string): Integer;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtImageData;
  Errors: TStringList;
  FileName: string;
  I: Integer;
  ImportError: string;
  InsertedIndices: TArray<Integer>;
  Pending: TList<TVectArtImageData>;
  StartIndex: Integer;
begin
  Result := 0;
  ErrorMessage := '';
  if (Document = nil) or (Document.CanvasLayer = nil) then
  begin
    ErrorMessage := '画像の配置先がありません';
    Exit;
  end;
  Pending := TList<TVectArtImageData>.Create;
  Errors := TStringList.Create;
  try
    for FileName in FileNames do
      if BuildImageData(Document, FileName, DropCenter, Pending.Count,
        Data, ImportError) then
        Pending.Add(Data)
      else
        AppendImportError(Errors, FileName, ImportError);
    if Pending.Count = 0 then
    begin
      ErrorMessage := Errors.Text.Trim;
      Exit;
    end;

    BeforeSelection := Document.GetSelectedLayerIndices;
    StartIndex := Document.LayerCount;
    SetLength(InsertedIndices, Pending.Count);
    Document.BeginUpdate;
    try
      for I := 0 to Pending.Count - 1 do
      begin
        Data := Pending[I];
        Data.Name := NextMapRakuLayerName(Document, 'Image');
        Pending[I] := Data;
        InsertedIndices[I] := Document.InsertImage(Document.LayerCount, Data);
      end;
      Document.SetSelectedLayers(InsertedIndices);
      AfterSelection := Document.GetSelectedLayerIndices;
    finally
      Document.EndUpdate;
    end;
    if EditHistory <> nil then
      EditHistory.AddApplied(TVectArtInsertImagesCommand.Create(Document,
        StartIndex, Pending.ToArray, BeforeSelection, AfterSelection));
    Result := Pending.Count;
    ErrorMessage := Errors.Text.Trim;
  finally
    Errors.Free;
    Pending.Free;
  end;
end;

end.

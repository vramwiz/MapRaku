// AIが既存の配置を把握し、現行形式の文字・装飾を新規作成するための読取情報。
unit MapRakuAutomationLayout;

interface

uses System.JSON, MapRakuDocument;

// 階層パスはこのDocumentスナップショット内だけで有効。JSON所有権を呼出側へ渡す。
function MapRakuAutomationGeometry(Document: TVectArtDocument): TJSONObject;
// 現行モデルとWriterで生成する作成例。完全なJSON Schemaではない。
function MapRakuAutomationCreationSchema: TJSONObject;

implementation

uses
  System.SysUtils, System.Types, Vcl.Graphics, MapRakuLayerGeometry,
  MapRakuDocumentJson, MapRakuFilters;

procedure AppendGeometry(Layer: TVectArtLayer; const Path: string;
  ParentVisible: Boolean; Entries: TJSONArray);
var
  Entry, Rect: TJSONObject;
  Bounds: TRectF;
  Group: TMapRakuGroupLayer;
  I: Integer;
begin
  Entry := TJSONObject.Create;
  Entries.AddElement(Entry);
  Entry.AddPair('layer_path', Path);
  Entry.AddPair('name', Layer.Name);
  Entry.AddPair('visible', TJSONBool.Create(Layer.Visible and ParentVisible));
  Entry.AddPair('locked', TJSONBool.Create(Layer.Locked));
  Entry.AddPair('opacity', TJSONNumber.Create(Layer.Opacity));
  if TryGetMapRakuLayerBounds(Layer, Bounds) then
  begin
    Rect := TJSONObject.Create;
    Rect.AddPair('left', TJSONNumber.Create(Bounds.Left));
    Rect.AddPair('top', TJSONNumber.Create(Bounds.Top));
    Rect.AddPair('right', TJSONNumber.Create(Bounds.Right));
    Rect.AddPair('bottom', TJSONNumber.Create(Bounds.Bottom));
    Entry.AddPair('bounds', Rect);
  end
  else
    Entry.AddPair('bounds', TJSONNull.Create);
  if Layer is TMapRakuGroupLayer then
  begin
    Group := TMapRakuGroupLayer(Layer);
    for I := 0 to Group.ChildCount - 1 do
      AppendGeometry(Group[I], Path + '/layers/' + IntToStr(I),
        ParentVisible and Layer.Visible, Entries);
  end;
end;

function MapRakuAutomationGeometry(Document: TVectArtDocument): TJSONObject;
var
  Entries: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('coordinate_origin', 'center');
    Result.AddPair('bounds_kind', 'transformed_geometry');
    Result.AddPair('effects_included', TJSONBool.Create(False));
    Result.AddPair('paths_are_persistent', TJSONBool.Create(False));
    Entries := TJSONArray.Create;
    Result.AddPair('layers', Entries);
    for I := 1 to Document.LayerCount - 1 do
      AppendGeometry(Document[I], '/layers/' + IntToStr(I - 1), True, Entries);
  except
    Result.Free;
    raise;
  end;
end;

function MapRakuAutomationCreationSchema: TJSONObject;
var
  Examples: TVectArtDocument;
  Text: TMapRakuTextLayer;
  Contour: TMapRakuContour;
  Shape: TMapRakuShapeLayer;
begin
  Examples := TVectArtDocument.Create;
  Result := TJSONObject.Create;
  try
    try
      Examples.SetCanvasSize(1280, 720);
      Text := TMapRakuTextLayer.Create('見出し', TRectF.Create(-500, -120, 100, 120),
        '見出しを入力', 'Yu Gothic UI', 80, 600, clYellow);
      Examples.InsertLayer(1, Text);
      Text.AddFilter(TMapRakuOutlineFilter.Create);
      Text.AddFilter(TMapRakuShadowFilter.Create);
      Examples.InsertLayer(2, TVectArtRectangleLayer.Create('帯',
        TRectF.Create(-550, 150, 550, 260), clNavy));
      Examples.InsertLayer(3, TMapRakuEllipseLayer.Create('円の装飾',
        TRectF.Create(300, -250, 500, -50), clYellow));
      Contour := Default(TMapRakuContour);
      SetLength(Contour.Vertices, 3);
      Contour.Vertices[0].Position := TPointF.Create(-100, -100);
      Contour.Vertices[1].Position := TPointF.Create(100, 0);
      Contour.Vertices[2].Position := TPointF.Create(-100, 100);
      Shape := TMapRakuShapeLayer.Create('三角形の装飾', [Contour]);
      Examples.InsertLayer(4, Shape);
      Shape.FillColor := clYellow;
      Result.AddPair('schema_kind', 'creation_examples');
      Result.AddPair('scope', 'text_with_outline_and_shadow,rectangle,ellipse,shape');
      Result.AddPair('usage', 'Copy needed layers into the latest snapshot; preserve existing layers and canvas.');
      Result.AddPair('color_encoding', 'Delphi TColor integer: 0x00BBGGRR');
      Result.AddPair('example_document', TJSONObject.ParseJSONValue(SerializeVectArtDocument(Examples)));
    except
      Result.Free;
      raise;
    end;
  finally
    Examples.Free;
  end;
end;

end.

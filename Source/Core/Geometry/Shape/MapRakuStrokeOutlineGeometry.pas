// 開いたPathの表示上の線を、編集可能な閉じたShape輪郭へ変換する。
unit MapRakuStrokeOutlineGeometry;

interface

uses
  MapRakuDocument;

function BuildMapRakuStrokeOutlineContours(PathLayer: TVectArtPathLayer):
  TArray<TMapRakuContour>;

implementation

uses
  System.Math, System.Skia, System.Types,
  {$IFDEF DEBUG}System.Classes, System.IOUtils, System.SysUtils,{$ENDIF}
  MapRakuShapeBooleanGeometry, MapRakuVariableWidthRenderer;

{$IFDEF DEBUG}
procedure WriteStrokeOutlineDebugLog(PathLayer: TVectArtPathLayer;
  const Contours: TArray<TMapRakuContour>);
var
  Builder: TStringBuilder;
  ContourIndex: Integer;
  I: Integer;
  Vertices: TArray<TMapRakuVertex>;
  WidthPoints: TArray<TMapRakuStrokeWidthPoint>;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.AppendLine('MapRaku stroke outline debug');
    Builder.AppendLine(Format('name=%s width=%.6f cap=%d style=%d',
      [PathLayer.Name, PathLayer.StrokeWidth, Ord(PathLayer.LineCap),
      Ord(PathLayer.MifStrokeStyle)]));
    Vertices := PathLayer.Vertices;
    Builder.AppendLine(Format('sourceVertices=%d', [Length(Vertices)]));
    for I := 0 to High(Vertices) do
      Builder.AppendLine(Format(
        'V[%d] pos=(%.6f,%.6f) kind=%d segment=%d in=(%.6f,%.6f) out=(%.6f,%.6f)',
        [I, Vertices[I].Position.X, Vertices[I].Position.Y,
        Ord(Vertices[I].Kind), Ord(Vertices[I].OutgoingSegment),
        Vertices[I].IncomingControl.X, Vertices[I].IncomingControl.Y,
        Vertices[I].OutgoingControl.X, Vertices[I].OutgoingControl.Y]));
    WidthPoints := PathLayer.WidthPoints;
    Builder.AppendLine(Format('widthPoints=%d', [Length(WidthPoints)]));
    for I := 0 to High(WidthPoints) do
      Builder.AppendLine(Format('W[%d] offset=%.6f left=%.6f right=%.6f',
        [I, WidthPoints[I].Offset, WidthPoints[I].LeftScale,
        WidthPoints[I].RightScale]));
    Builder.AppendLine(Format('contours=%d', [Length(Contours)]));
    for ContourIndex := 0 to High(Contours) do
    begin
      Builder.AppendLine(Format('C[%d] vertices=%d', [ContourIndex,
        Length(Contours[ContourIndex].Vertices)]));
      for I := 0 to High(Contours[ContourIndex].Vertices) do
        Builder.AppendLine(Format(
          'C[%d].V[%d] pos=(%.6f,%.6f) kind=%d segment=%d in=(%.6f,%.6f) out=(%.6f,%.6f)',
          [ContourIndex, I,
          Contours[ContourIndex].Vertices[I].Position.X,
          Contours[ContourIndex].Vertices[I].Position.Y,
          Ord(Contours[ContourIndex].Vertices[I].Kind),
          Ord(Contours[ContourIndex].Vertices[I].OutgoingSegment),
          Contours[ContourIndex].Vertices[I].IncomingControl.X,
          Contours[ContourIndex].Vertices[I].IncomingControl.Y,
          Contours[ContourIndex].Vertices[I].OutgoingControl.X,
          Contours[ContourIndex].Vertices[I].OutgoingControl.Y]));
    end;
    TFile.WriteAllText(TPath.Combine(TPath.GetTempPath,
      'MapRaku-stroke-outline-debug.log'), Builder.ToString,
      TEncoding.UTF8);
  finally
    Builder.Free;
  end;
end;
{$ENDIF}

function CompactStrokeOutlineVertices(
  const Source: TArray<TMapRakuContour>): TArray<TMapRakuContour>;
const
  MERGE_DISTANCE = 0.1;
var
  AbsoluteIncoming: TPointF;
  AbsoluteOutgoing: TPointF;
  ContourIndex: Integer;
  I: Integer;
  J: Integer;
  Merged: TMapRakuVertex;
begin
  Result := Copy(Source);
  for ContourIndex := 0 to High(Result) do
    Result[ContourIndex].Vertices := Copy(Source[ContourIndex].Vertices);
  for ContourIndex := 0 to High(Result) do
  begin
    I := 0;
    while I < High(Result[ContourIndex].Vertices) do
      if Hypot(Result[ContourIndex].Vertices[I + 1].Position.X -
        Result[ContourIndex].Vertices[I].Position.X,
        Result[ContourIndex].Vertices[I + 1].Position.Y -
        Result[ContourIndex].Vertices[I].Position.Y) <= MERGE_DISTANCE then
      begin
        Merged := Result[ContourIndex].Vertices[I];
        AbsoluteIncoming := TPointF.Create(Merged.Position.X +
          Merged.IncomingControl.X, Merged.Position.Y +
          Merged.IncomingControl.Y);
        AbsoluteOutgoing := TPointF.Create(
          Result[ContourIndex].Vertices[I + 1].Position.X +
          Result[ContourIndex].Vertices[I + 1].OutgoingControl.X,
          Result[ContourIndex].Vertices[I + 1].Position.Y +
          Result[ContourIndex].Vertices[I + 1].OutgoingControl.Y);
        Merged.Position := TPointF.Create(
          (Merged.Position.X +
            Result[ContourIndex].Vertices[I + 1].Position.X) * 0.5,
          (Merged.Position.Y +
            Result[ContourIndex].Vertices[I + 1].Position.Y) * 0.5);
        Merged.IncomingControl := TPointF.Create(AbsoluteIncoming.X -
          Merged.Position.X, AbsoluteIncoming.Y - Merged.Position.Y);
        Merged.OutgoingSegment :=
          Result[ContourIndex].Vertices[I + 1].OutgoingSegment;
        Merged.OutgoingControl := TPointF.Create(AbsoluteOutgoing.X -
          Merged.Position.X, AbsoluteOutgoing.Y - Merged.Position.Y);
        if (Merged.OutgoingSegment = slskCubicBezier) or
          (Length(Result[ContourIndex].Vertices) > 2) and
          (Result[ContourIndex].Vertices[(I + Length(
            Result[ContourIndex].Vertices) - 1) mod Length(
            Result[ContourIndex].Vertices)].OutgoingSegment =
            slskCubicBezier) then
          Merged.Kind := slvkBezier
        else
          Merged.Kind := slvkSharp;
        Result[ContourIndex].Vertices[I] := Merged;
        for J := I + 1 to High(Result[ContourIndex].Vertices) - 1 do
          Result[ContourIndex].Vertices[J] :=
            Result[ContourIndex].Vertices[J + 1];
        SetLength(Result[ContourIndex].Vertices,
          Length(Result[ContourIndex].Vertices) - 1);
      end
      else
        Inc(I);
  end;
end;

function BuildCenterPath(PathLayer: TVectArtPathLayer): ISkPath;
var
  Builder: ISkPathBuilder;
  I: Integer;
  Vertices: TArray<TMapRakuVertex>;
begin
  Result := nil;
  Vertices := PathLayer.Vertices;
  if Length(Vertices) < 2 then
    Exit;
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(Vertices[0].Position);
  for I := 0 to High(Vertices) - 1 do
    if Vertices[I].OutgoingSegment = slskCubicBezier then
      Builder.CubicTo(
        TPointF.Create(Vertices[I].Position.X +
          Vertices[I].OutgoingControl.X, Vertices[I].Position.Y +
          Vertices[I].OutgoingControl.Y),
        TPointF.Create(Vertices[I + 1].Position.X +
          Vertices[I + 1].IncomingControl.X, Vertices[I + 1].Position.Y +
          Vertices[I + 1].IncomingControl.Y), Vertices[I + 1].Position)
    else
      Builder.LineTo(Vertices[I + 1].Position);
  Result := Builder.Detach;
end;

function UniformWidthPoints: TArray<TMapRakuStrokeWidthPoint>;
begin
  SetLength(Result, 2);
  Result[0].Offset := 0;
  Result[0].LeftScale := 1;
  Result[0].RightScale := 1;
  Result[1].Offset := 1;
  Result[1].LeftScale := 1;
  Result[1].RightScale := 1;
end;

function BuildMapRakuStrokeOutlineContours(PathLayer: TVectArtPathLayer):
  TArray<TMapRakuContour>;
var
  CenterPath: ISkPath;
  DashIntervals: TArray<Single>;
  OutlinePath: ISkPath;
  Paint: ISkPaint;
  WidthPoints: TArray<TMapRakuStrokeWidthPoint>;
begin
  Result := nil;
  if (PathLayer = nil) or PathLayer.Closed or
    (PathLayer.StrokeWidth <= 0) then
    Exit;
  CenterPath := BuildCenterPath(PathLayer);
  if CenterPath = nil then
    Exit;
  WidthPoints := PathLayer.WidthPoints;
  if PathLayer.MifStrokeStyle = vssSolid then
  begin
    if Length(WidthPoints) < 2 then
      WidthPoints := UniformWidthPoints;
    OutlinePath := BuildMapRakuVariableWidthPath(CenterPath,
      WidthPoints, PathLayer.StrokeWidth, PathLayer.LineCap,
      PathLayer.Vertices);
  end
  else
  begin
    Paint := TSkPaint.Create;
    Paint.Style := TSkPaintStyle.Stroke;
    Paint.StrokeWidth := PathLayer.StrokeWidth;
    Paint.StrokeJoin := TSkStrokeJoin.Miter;
    case PathLayer.LineCap of
      vlcRound: Paint.StrokeCap := TSkStrokeCap.Round;
    else
      Paint.StrokeCap := TSkStrokeCap.Square;
    end;
    DashIntervals := VectArtStrokeDashIntervals(PathLayer.MifStrokeStyle,
      PathLayer.StrokeWidth);
    if Length(DashIntervals) > 0 then
      Paint.PathEffect := TSkPathEffect.MakeDash(DashIntervals, 0);
    OutlinePath := Paint.GetFillPath(CenterPath);
  end;
  // 均一幅の丸端はSkiaのConicとして返るため、各円弧を1本の3次ベジェへ
  // まとめ、変換後に多数の編集点が並ばないようにする。
  Result := CompactStrokeOutlineVertices(
    ConvertSkPathToCompactMapRakuShapeContours(OutlinePath));
  {$IFDEF DEBUG}
  WriteStrokeOutlineDebugLog(PathLayer, Result);
  {$ENDIF}
end;

end.

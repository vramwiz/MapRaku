// Draws outlined editor shapes by applying the shared screen-space contrast style.
unit MapRakuOverlayShapes;

interface

uses
  System.Types, System.UITypes, Vcl.Direct2D, Vcl.Graphics,
  MapRakuOverlayPrimitives;

// Draws an unfilled rectangular guide and restores the target drawing state.
procedure DrawOverlayFrameRect(Target: TCanvas; const Bounds: TRect;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR; Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;
// Direct2D counterpart of DrawOverlayFrameRect with the same exclusive rectangle bounds.
procedure DrawOverlayFrameRect(Target: TDirect2DCanvas; const Bounds: TRect;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR; Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;
// Draws an unfilled elliptical guide while retaining a semantic core color.
procedure DrawOverlayEllipse(Target: TCanvas; const Bounds: TRect;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;
// Direct2D counterpart of DrawOverlayEllipse with matching screen-pixel widths.
procedure DrawOverlayEllipse(Target: TDirect2DCanvas; const Bounds: TRect;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;
// Draws an unfilled rounded-rectangle guide; Radius is the screen-space corner radius.
procedure DrawOverlayRoundRect(Target: TCanvas; const Bounds: TRect; Radius: Integer;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;
// Direct2D counterpart of DrawOverlayRoundRect with an equivalent screen-space radius.
procedure DrawOverlayRoundRect(Target: TDirect2DCanvas; const Bounds: TRect; Radius: Integer;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;
// Draws a filled pie preview with a contrasting boundary and restores pen and brush state.
procedure DrawOverlayPie(Target: TCanvas; const Bounds: TRect;
  const StartPoint, EndPoint: TPoint; FillColor: TColor;
  BorderColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR); overload;
// Direct2D counterpart of DrawOverlayPie with matching fill, boundary, and state restoration.
procedure DrawOverlayPie(Target: TDirect2DCanvas; const Bounds: TRect;
  const StartPoint, EndPoint: TPoint; FillColor: TColor;
  BorderColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR); overload;

implementation

procedure DrawOverlayFrameRect(Target: TCanvas; const Bounds: TRect;
  CoreColor: TColor; Style: TPenStyle; HaloWidth, CoreWidth: Integer);
var
  Bottom: Integer;
  Points: array[0..4] of TPoint;
  Right: Integer;
begin
  if Bounds.IsEmpty then
    Exit;
  Right := Bounds.Right - 1;
  Bottom := Bounds.Bottom - 1;
  Points[0] := Bounds.TopLeft;
  Points[1] := Point(Right, Bounds.Top);
  Points[2] := Point(Right, Bottom);
  Points[3] := Point(Bounds.Left, Bottom);
  Points[4] := Points[0];
  DrawOverlayPolyline(Target, Points, CoreColor, Style, HaloWidth, CoreWidth);
end;

procedure DrawOverlayFrameRect(Target: TDirect2DCanvas; const Bounds: TRect;
  CoreColor: TColor; Style: TPenStyle; HaloWidth, CoreWidth: Integer);
var
  Bottom: Integer;
  Points: array[0..4] of TPoint;
  Right: Integer;
begin
  if Bounds.IsEmpty then
    Exit;
  Right := Bounds.Right - 1;
  Bottom := Bounds.Bottom - 1;
  Points[0] := Bounds.TopLeft;
  Points[1] := Point(Right, Bounds.Top);
  Points[2] := Point(Right, Bottom);
  Points[3] := Point(Bounds.Left, Bottom);
  Points[4] := Points[0];
  DrawOverlayPolyline(Target, Points, CoreColor, Style, HaloWidth, CoreWidth);
end;

procedure DrawOverlayEllipse(Target: TCanvas; const Bounds: TRect;
  CoreColor: TColor; HaloWidth, CoreWidth: Integer);
var
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsClear;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.Ellipse(Bounds);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.Ellipse(Bounds);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayEllipse(Target: TDirect2DCanvas; const Bounds: TRect;
  CoreColor: TColor; HaloWidth, CoreWidth: Integer);
var
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsClear;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.Ellipse(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.Ellipse(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayRoundRect(Target: TCanvas; const Bounds: TRect; Radius: Integer;
  CoreColor: TColor; HaloWidth, CoreWidth: Integer);
var
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsClear;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.RoundRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      Radius * 2, Radius * 2);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.RoundRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      Radius * 2, Radius * 2);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayRoundRect(Target: TDirect2DCanvas; const Bounds: TRect;
  Radius: Integer; CoreColor: TColor; HaloWidth, CoreWidth: Integer);
var
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsClear;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := HaloWidth;
    Target.RoundRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      Radius * 2, Radius * 2);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.RoundRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      Radius * 2, Radius * 2);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayPie(Target: TCanvas; const Bounds: TRect;
  const StartPoint, EndPoint: TPoint; FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
    Target.Pie(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      StartPoint.X, StartPoint.Y, EndPoint.X, EndPoint.Y);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
    Target.Pie(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      StartPoint.X, StartPoint.Y, EndPoint.X, EndPoint.Y);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayPie(Target: TDirect2DCanvas; const Bounds: TRect;
  const StartPoint, EndPoint: TPoint; FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.Pen.Style := psSolid;
    Target.Pen.Color := SCREEN_LAYOUT_OVERLAY_HALO_COLOR;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
    Target.Pie(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      StartPoint.X, StartPoint.Y, EndPoint.X, EndPoint.Y);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
    Target.Pie(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom,
      StartPoint.X, StartPoint.Y, EndPoint.X, EndPoint.Y);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

end.

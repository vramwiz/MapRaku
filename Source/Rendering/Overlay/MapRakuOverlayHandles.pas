// Draws filled editor handles while preserving their semantic fill and border colors.
unit MapRakuOverlayHandles;

interface

uses
  System.Types, System.UITypes, Vcl.Direct2D, Vcl.Graphics,
  MapRakuOverlayPrimitives;

// Draws a rectangular handle with a contrast halo and restores brush and pen state.
procedure DrawOverlayHandleRect(Target: TCanvas; const Bounds: TRect;
  FillColor: TColor = clWhite;
  BorderColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR); overload;
// Direct2D counterpart of DrawOverlayHandleRect with identical state-restoration behavior.
procedure DrawOverlayHandleRect(Target: TDirect2DCanvas; const Bounds: TRect;
  FillColor: TColor = clWhite;
  BorderColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR); overload;
// Draws an elliptical handle; fill and border colors retain the handle's editing meaning.
procedure DrawOverlayHandleEllipse(Target: TCanvas; const Bounds: TRect;
  FillColor, BorderColor: TColor); overload;
// Direct2D counterpart of DrawOverlayHandleEllipse with matching semantic colors.
procedure DrawOverlayHandleEllipse(Target: TDirect2DCanvas; const Bounds: TRect;
  FillColor, BorderColor: TColor); overload;
// Draws a polygonal handle and allows compact internal marks to suppress the wider halo.
procedure DrawOverlayHandlePolygon(Target: TCanvas; const Points: array of TPoint;
  FillColor, BorderColor: TColor;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;
// Direct2D counterpart of DrawOverlayHandlePolygon; fewer than three points perform no drawing.
procedure DrawOverlayHandlePolygon(Target: TDirect2DCanvas;
  const Points: array of TPoint; FillColor, BorderColor: TColor;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH); overload;

implementation

uses
  MapRakuOverlayShapes;

procedure DrawOverlayHandleRect(Target: TCanvas; const Bounds: TRect;
  FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
begin
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.FillRect(Bounds);
    DrawOverlayFrameRect(Target, Bounds, BorderColor);
  finally
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandleRect(Target: TDirect2DCanvas; const Bounds: TRect;
  FillColor, BorderColor: TColor);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
begin
  OldBrushColor := Target.Brush.Color;
  OldBrushStyle := Target.Brush.Style;
  try
    Target.Brush.Style := bsSolid;
    Target.Brush.Color := FillColor;
    Target.FillRect(Bounds);
    DrawOverlayFrameRect(Target, Bounds, BorderColor);
  finally
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandleEllipse(Target: TCanvas; const Bounds: TRect;
  FillColor, BorderColor: TColor);
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
    Target.Ellipse(Bounds);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
    Target.Ellipse(Bounds);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandleEllipse(Target: TDirect2DCanvas; const Bounds: TRect;
  FillColor, BorderColor: TColor);
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
    Target.Ellipse(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
    Target.Ellipse(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandlePolygon(Target: TCanvas; const Points: array of TPoint;
  FillColor, BorderColor: TColor; HaloWidth, CoreWidth: Integer);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  if Length(Points) < 3 then
    Exit;
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
    Target.Pen.Width := HaloWidth;
    Target.Polygon(Points);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := CoreWidth;
    Target.Polygon(Points);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

procedure DrawOverlayHandlePolygon(Target: TDirect2DCanvas;
  const Points: array of TPoint; FillColor, BorderColor: TColor;
  HaloWidth, CoreWidth: Integer);
var
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  if Length(Points) < 3 then
    Exit;
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
    Target.Pen.Width := HaloWidth;
    Target.Polygon(Points);
    Target.Brush.Style := bsClear;
    Target.Pen.Color := BorderColor;
    Target.Pen.Width := CoreWidth;
    Target.Polygon(Points);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
    Target.Brush.Color := OldBrushColor;
    Target.Brush.Style := OldBrushStyle;
  end;
end;

end.

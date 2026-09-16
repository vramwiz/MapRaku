// Draws high-contrast editor lines without owning overlay geometry or interaction state.
unit MapRakuOverlayPrimitives;

interface

uses
  System.Types, System.UITypes, Vcl.Direct2D, Vcl.Graphics;

const
  SCREEN_LAYOUT_OVERLAY_HALO_COLOR = clWhite; // Contrasts with dark artwork behind the editor overlay.
  SCREEN_LAYOUT_OVERLAY_CORE_COLOR = clBlack; // Preserves a crisp edge on light artwork.
  SCREEN_LAYOUT_OVERLAY_HALO_WIDTH = 2;       // Screen pixels; deliberately independent of document zoom.
  SCREEN_LAYOUT_OVERLAY_CORE_WIDTH = 1;       // Screen pixels used for the semantic line color.

// Draws one screen-space line as a halo pass followed by a core pass and restores the target pen.
procedure DrawOverlayLine(Target: TCanvas; const StartPoint, EndPoint: TPoint;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR; Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
  HaloColor: TColor = SCREEN_LAYOUT_OVERLAY_HALO_COLOR); overload;
// Direct2D counterpart of DrawOverlayLine with identical screen-pixel and state-restoration behavior.
procedure DrawOverlayLine(Target: TDirect2DCanvas; const StartPoint, EndPoint: TPoint;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR; Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
  HaloColor: TColor = SCREEN_LAYOUT_OVERLAY_HALO_COLOR); overload;
// Draws a point sequence with the same contrast and state-restoration rules as a single line.
procedure DrawOverlayPolyline(Target: TCanvas; const Points: array of TPoint;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR; Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
  HaloColor: TColor = SCREEN_LAYOUT_OVERLAY_HALO_COLOR); overload;
// Direct2D counterpart of DrawOverlayPolyline; an empty or single-point input performs no drawing.
procedure DrawOverlayPolyline(Target: TDirect2DCanvas; const Points: array of TPoint;
  CoreColor: TColor = SCREEN_LAYOUT_OVERLAY_CORE_COLOR; Style: TPenStyle = psSolid;
  HaloWidth: Integer = SCREEN_LAYOUT_OVERLAY_HALO_WIDTH;
  CoreWidth: Integer = SCREEN_LAYOUT_OVERLAY_CORE_WIDTH;
  HaloColor: TColor = SCREEN_LAYOUT_OVERLAY_HALO_COLOR); overload;

implementation

procedure DrawOverlayLine(Target: TCanvas; const StartPoint, EndPoint: TPoint;
  CoreColor: TColor; Style: TPenStyle; HaloWidth, CoreWidth: Integer;
  HaloColor: TColor);
var
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  try
    Target.Pen.Style := Style;
    Target.Pen.Color := HaloColor;
    Target.Pen.Width := HaloWidth;
    Target.MoveTo(StartPoint.X, StartPoint.Y);
    Target.LineTo(EndPoint.X, EndPoint.Y);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.MoveTo(StartPoint.X, StartPoint.Y);
    Target.LineTo(EndPoint.X, EndPoint.Y);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
  end;
end;

procedure DrawOverlayLine(Target: TDirect2DCanvas; const StartPoint, EndPoint: TPoint;
  CoreColor: TColor; Style: TPenStyle; HaloWidth, CoreWidth: Integer;
  HaloColor: TColor);
var
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  try
    Target.Pen.Style := Style;
    Target.Pen.Color := HaloColor;
    Target.Pen.Width := HaloWidth;
    Target.MoveTo(StartPoint.X, StartPoint.Y);
    Target.LineTo(EndPoint.X, EndPoint.Y);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.MoveTo(StartPoint.X, StartPoint.Y);
    Target.LineTo(EndPoint.X, EndPoint.Y);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
  end;
end;

procedure DrawOverlayPolyline(Target: TCanvas; const Points: array of TPoint;
  CoreColor: TColor; Style: TPenStyle; HaloWidth, CoreWidth: Integer;
  HaloColor: TColor);
var
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  if Length(Points) < 2 then
    Exit;
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  try
    Target.Pen.Style := Style;
    Target.Pen.Color := HaloColor;
    Target.Pen.Width := HaloWidth;
    Target.Polyline(Points);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.Polyline(Points);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
  end;
end;

procedure DrawOverlayPolyline(Target: TDirect2DCanvas; const Points: array of TPoint;
  CoreColor: TColor; Style: TPenStyle; HaloWidth, CoreWidth: Integer;
  HaloColor: TColor);
var
  OldPenColor: TColor;
  OldPenStyle: TPenStyle;
  OldPenWidth: Integer;
begin
  if Length(Points) < 2 then
    Exit;
  OldPenColor := Target.Pen.Color;
  OldPenStyle := Target.Pen.Style;
  OldPenWidth := Target.Pen.Width;
  try
    Target.Pen.Style := Style;
    Target.Pen.Color := HaloColor;
    Target.Pen.Width := HaloWidth;
    Target.Polyline(Points);
    Target.Pen.Color := CoreColor;
    Target.Pen.Width := CoreWidth;
    Target.Polyline(Points);
  finally
    Target.Pen.Color := OldPenColor;
    Target.Pen.Style := OldPenStyle;
    Target.Pen.Width := OldPenWidth;
  end;
end;

end.

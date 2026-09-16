// 編集対象となる用紙とオブジェクトレイヤーを一元管理する。
// レイヤー配列の先頭を最背面、末尾を最前面とする。
unit MapRakuDocument;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.Types,
  Vcl.Graphics, MapRakuFilters, MapRakuPaintStyles,
  MapRakuProjectiveTransform;

const
  SCREEN_LAYOUT_TEXT_PATH_CHARACTER_SCALE_MIN = 0.1;
  SCREEN_LAYOUT_TEXT_PATH_CHARACTER_SCALE_MAX = 10.0;
  SCREEN_LAYOUT_TEXT_LETTER_SPACING_MIN = -0.5;
  SCREEN_LAYOUT_TEXT_LETTER_SPACING_MAX = 1.0;
  SCREEN_LAYOUT_TEXT_LINE_SPACING_MIN = -0.5;
  SCREEN_LAYOUT_TEXT_LINE_SPACING_MAX = 3.0;

type
  TMapRakuTextAlignment = (sltaTopLeft, sltaTopCenter,
    sltaTopRight, sltaMiddleLeft, sltaMiddleCenter, sltaMiddleRight,
    sltaBottomLeft, sltaBottomCenter, sltaBottomRight);
  TMapRakuTextPathAttachment = (sltpaBottom, sltpaTop, sltpaLeft,
    sltpaRight);
  TMapRakuTextTransformMode = (slttmUniformScale, slttmFrameFit);

  TVectArtLayerKind = (vlkCanvas, vlkRectangle, vlkRoundedRectangle,
    vlkPath, vlkImage, vlkShape, vlkEllipse, vlkArc, vlkRectangleLine,
    vlkRoundedRectangleLine, vlkEllipseLine, vlkEllipseArcShape, vlkText,
    vlkTextPath, vlkGroup, vlkMapLevelBoundary);
  TVectArtImageSourceKind = (visImage, visLogo);
  TVectArtImagePoints = array[0..3] of TPointF;
  // WebArt Designerの線種コンボとMIF vector stroke style 0..8を同順で保持する。
  TVectArtMifStrokeStyle = (vssSolid, vssDotted, vssShortDash, vssDashDot,
    vssDashDotDot, vssSparseDotted, vssMediumDash, vssLongDashDot,
    vssLongDash);
  // 線端を四角、丸、先端角90度の三角から選ぶ。
  TVectArtLineCap = (vlcSquare, vlcRound, vlcTriangle);
  // Path中心線の周囲を基準線幅一定または幅プロファイルで描く。
  TMapRakuStrokeWidthMode = (slwmUniform, slwmVariable);
  // 各頂点から次頂点へ向かう閉輪郭区間の表現形式。
  TMapRakuSegmentKind = (slskLine, slskCubicBezier);
  // Shape編集時にユーザーが選ぶ頂点の接続形式。
  TMapRakuVertexKind = (slvkSharp, slvkBezier);
  // 穴や重複輪郭を含むShapeの内外判定規則。
  TMapRakuFillRule = (slfrEvenOdd, slfrNonZero);
  TMapRakuCrossingKind = (mckNormal, mckRailroadCrossing, mckOverpass,
    mckBridge, mckRailOverpass, mckNone, mckUnderpass, mckTunnel);

  TMapRakuCrossingRelation = class
  public
    ObjectAId: string;
    ObjectBId: string;
    Kind: TMapRakuCrossingKind;
    UpperObjectId: string;
    RangeMargin: Single;
  end;

  TMapRakuVertex = record
    Position: TPointF;              // 頂点のドキュメント座標。
    IncomingControl: TPointF;       // 頂点から入力側制御点への相対座標。
    OutgoingControl: TPointF;       // 頂点から出力側制御点への相対座標。
    OutgoingSegment: TMapRakuSegmentKind; // 次頂点までの区間種別。
    Kind: TMapRakuVertexKind;  // 鋭角または滑らかなベジェ接続。
  end;

  TMapRakuStrokeWidthPoint = record
    Offset: Single;     // 中心Path全長に対する0..1の位置。
    LeftScale: Single;  // 基準線幅の半分に対する進行方向左側の倍率。
    RightScale: Single; // 基準線幅の半分に対する進行方向右側の倍率。
  end;

  TMapRakuContour = record
    Vertices: TArray<TMapRakuVertex>; // 終端から先頭へ閉じる頂点列。
    // 閉輪郭の区間数を返す。終端から先頭への区間も1本に数える。
    function SegmentCount: Integer;
  end;
  TVectArtLayer = class
  private
    FFilters: TObjectList<TMapRakuFilter>;
    FFlipHorizontal: Boolean;
    FFlipVertical: Boolean;
    FKind: TVectArtLayerKind;
    FPersistentId: string;
    FLocked: Boolean;
    FName: string;
    FOpacity: Single;
    FPaintStyle: TMapRakuPaintStyle;
    FVisible: Boolean;
    FTransform: TMapRakuTransform;
    function GetFilter(Index: Integer): TMapRakuFilter;
    function GetFilterCount: Integer;
  protected
    constructor Create(AKind: TVectArtLayerKind; const AName: string);
  public
    destructor Destroy; override;
    procedure AddFilter(Filter: TMapRakuFilter);
    procedure ClearFilters;
    procedure DeleteFilter(Index: Integer);
    function ExtractFilter(Index: Integer): TMapRakuFilter;
    procedure InsertFilter(Index: Integer; Filter: TMapRakuFilter);
    procedure MoveFilter(FromIndex, ToIndex: Integer);
    // Pathと文字パスが共有する頂点編集対象を返す。非対応レイヤーではnilを返す。
    function EditablePathVertices: TArray<TMapRakuVertex>; virtual;
    // Path編集で更新された頂点列を受け取る。非対応レイヤーでは何もしない。
    procedure AssignEditablePathVertices(
      const Value: TArray<TMapRakuVertex>); virtual;
    // 既存Path編集処理を利用できるレイヤーならTrueを返す。
    function SupportsPathEditing: Boolean; virtual;
    property FilterCount: Integer read GetFilterCount;
    property Filters[Index: Integer]: TMapRakuFilter read GetFilter;
    // 文字など座標だけでは鏡像を表せない内容を、ローカル中心で反転する状態。
    property FlipHorizontal: Boolean read FFlipHorizontal write FFlipHorizontal;
    property FlipVertical: Boolean read FFlipVertical write FFlipVertical;
    property Kind: TVectArtLayerKind read FKind;
    // 保存後も交差関係から同じ対象を参照できる安定ID。
    property PersistentId: string read FPersistentId write FPersistentId;
    property Locked: Boolean read FLocked write FLocked;
    property Name: string read FName write FName;
    property Opacity: Single read FOpacity write FOpacity;
    // レイヤーの主色（塗り、または線）へ適用する共通描画スタイル。
    property PaintStyle: TMapRakuPaintStyle read FPaintStyle
      write FPaintStyle;
    property Visible: Boolean read FVisible write FVisible;
    // 元の編集データを保ったまま表示へ適用する射影変換。
    property Transform: TMapRakuTransform read FTransform write FTransform;
  end;

  // 複数レイヤーを積層順のまま所有する。子の座標はDocument座標のまま保持する。
  TMapRakuGroupLayer = class(TVectArtLayer)
  private
    FMapSymbol: Boolean;
    FMapSurface: Boolean;
    FChildren: TObjectList<TVectArtLayer>;
    function GetChild(Index: Integer): TVectArtLayer;
    function GetChildCount: Integer;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    procedure AddChild(Layer: TVectArtLayer);
    function ExtractChild(Index: Integer): TVectArtLayer;
    procedure InsertChild(Index: Integer; Layer: TVectArtLayer);
    property MapSymbol: Boolean read FMapSymbol write FMapSymbol;
    property MapSurface: Boolean read FMapSurface write FMapSurface;
    property ChildCount: Integer read GetChildCount;
    property Children[Index: Integer]: TVectArtLayer read GetChild; default;
  end;

  // 描画せず、レイヤーリスト上で同じ高さの区間を分割する境界。
  TMapRakuLevelBoundaryLayer = class(TVectArtLayer)
  public
    constructor Create(const AName:string='高さの区切り');
  end;

  TVectArtCanvasLayer = class(TVectArtLayer)
  private
    FBackgroundColor: TColor;
    FHeight: Integer;
    FTransparent: Boolean;
    FWidth: Integer;
  public
    constructor Create(AWidth, AHeight: Integer; AColor: TColor);
    property BackgroundColor: TColor read FBackgroundColor
      write FBackgroundColor;
    property Height: Integer read FHeight write FHeight;
    property Transparent: Boolean read FTransparent write FTransparent;
    property Width: Integer read FWidth write FWidth;
  end;

  TVectArtRectangleLayer = class(TVectArtLayer)
  private
    FBounds: TRectF;
    FFillColor: TColor;
    FRotationDegrees: Single;
  protected
    constructor CreateWithKind(AKind: TVectArtLayerKind;
      const AName: string; const ABounds: TRectF; AFillColor: TColor);
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      AFillColor: TColor);
    property Bounds: TRectF read FBounds write FBounds;
    property FillColor: TColor read FFillColor write FFillColor;
    property RotationDegrees: Single read FRotationDegrees
      write FRotationDegrees;
  end;

  TVectArtRectangleData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Bounds: TRectF;                         // 回転前の基本矩形。
    FillColor: TColor;                      // 内部の塗り色。
    PaintStyle: TMapRakuPaintStyle;    // 単色以外を含む内部の描画スタイル。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single;                // 中心回りの時計回り角度。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TMapRakuCornerRadii = record
    TopLeft: Single;     // 左上隅の円弧半径。
    TopRight: Single;    // 右上隅の円弧半径。
    BottomRight: Single; // 右下隅の円弧半径。
    BottomLeft: Single;  // 左下隅の円弧半径。
  end;

  TMapRakuRoundedRectangleLayer = class(TVectArtRectangleLayer)
  private
    FCornerRadii: TMapRakuCornerRadii;
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      AFillColor: TColor; const ACornerRadii: TMapRakuCornerRadii);
    property CornerRadii: TMapRakuCornerRadii read FCornerRadii
      write FCornerRadii;
  end;

  TMapRakuRoundedRectangleData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Bounds: TRectF;                         // 回転前の基本矩形。
    CornerRadii: TMapRakuCornerRadii; // 左上から時計回りの角丸半径。
    FillColor: TColor;                      // 内部の塗り色。
    PaintStyle: TMapRakuPaintStyle;    // 単色以外を含む内部の描画スタイル。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single;                // 中心回りの時計回り角度。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TMapRakuEllipseLayer = class(TVectArtRectangleLayer)
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      AFillColor: TColor);
  end;

  TMapRakuEllipseData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Bounds: TRectF;          // 回転前の楕円へ外接する基本矩形。
    FillColor: TColor;       // 楕円内部の塗り色。
    PaintStyle: TMapRakuPaintStyle; // 単色以外を含む内部の描画スタイル。
    Locked: Boolean;         // 編集を禁止する状態。
    Name: string;            // レイヤー一覧の表示名。
    Opacity: Single;         // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single; // 楕円中心回りの時計回り角度。
    Visible: Boolean;        // 描画対象に含める状態。
  end;

  TMapRakuTextLayer = class(TVectArtRectangleLayer)
  private
    FAlignment: TMapRakuTextAlignment;
    FFontFamily: string;
    FFontSize: Single;
    FFontStyle: TFontStyles;
    FIndividualLetterSpacingRatios: TArray<Single>;
    FLetterSpacingRatio: Single;
    FLineSpacingRatio: Single;
    FText: string;
    FTransformMode: TMapRakuTextTransformMode;
    FWrapWidth: Single;
    function GetIndividualLetterSpacingRatios: TArray<Single>;
    procedure SetIndividualLetterSpacingRatios(
      const Value: TArray<Single>);
    procedure SetLetterSpacingRatio(Value: Single);
    procedure SetLineSpacingRatio(Value: Single);
  protected
    procedure SetText(const Value: string); virtual;
    constructor CreateWithKind(AKind: TVectArtLayerKind;
      const AName: string; const ABounds: TRectF;
      const AText, AFontFamily: string; AFontSize, AWrapWidth: Single;
      ATextColor: TColor);
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      const AText, AFontFamily: string; AFontSize, AWrapWidth: Single;
      ATextColor: TColor);
    property Alignment: TMapRakuTextAlignment read FAlignment
      write FAlignment;
    property FontFamily: string read FFontFamily write FFontFamily;
    property FontSize: Single read FFontSize write FFontSize;
    property FontStyle: TFontStyles read FFontStyle write FFontStyle;
    property IndividualLetterSpacingRatios: TArray<Single>
      read GetIndividualLetterSpacingRatios
      write SetIndividualLetterSpacingRatios;
    property LetterSpacingRatio: Single read FLetterSpacingRatio
      write SetLetterSpacingRatio;
    property LineSpacingRatio: Single read FLineSpacingRatio
      write SetLineSpacingRatio;
    property Text: string read FText write SetText;
    property TransformMode: TMapRakuTextTransformMode
      read FTransformMode write FTransformMode;
    property WrapWidth: Single read FWrapWidth write FWrapWidth;
  end;

  // 文字書式と、指定した文字セル面を沿わせる開いた連続線を1レイヤーに保持する。
  TMapRakuTextPathLayer = class(TMapRakuTextLayer)
  private
    FAttachment: TMapRakuTextPathAttachment;
    FCharacterPathOffsets: TArray<Single>;
    FCharacterPositionManual: TArray<Boolean>;
    FCharacterScales: TArray<Single>;
    FVertices: TArray<TMapRakuVertex>;
    function GetCharacterPathOffsets: TArray<Single>;
    function GetCharacterPositionManual: TArray<Boolean>;
    function GetCharacterScales: TArray<Single>;
    procedure SetCharacterPathOffsets(const Value: TArray<Single>);
    procedure SetCharacterPositionManual(const Value: TArray<Boolean>);
    procedure SetCharacterScales(const Value: TArray<Single>);
  protected
    procedure SetText(const Value: string); override;
  public
    // 文字書式と表示枠に加え、文字の基準線となる開いたPathを複製して保持する。
    constructor Create(const AName: string; const ABounds: TRectF;
      const AText, AFontFamily: string; AFontSize, AWrapWidth: Single;
      ATextColor: TColor; const AVertices: TArray<TMapRakuVertex>);
    // 内包Pathの独立した頂点配列を共通Path編集処理へ返す。
    function EditablePathVertices: TArray<TMapRakuVertex>; override;
    // 共通Path編集処理から受け取った頂点列を内包Pathへ複製する。
    procedure AssignEditablePathVertices(
      const Value: TArray<TMapRakuVertex>); override;
    // このレイヤーが共通Path編集処理を利用できることを返す。
    function SupportsPathEditing: Boolean; override;
    property Attachment: TMapRakuTextPathAttachment read FAttachment
      write FAttachment;
    property CharacterPathOffsets: TArray<Single>
      read GetCharacterPathOffsets write SetCharacterPathOffsets;
    property CharacterPositionManual: TArray<Boolean>
      read GetCharacterPositionManual write SetCharacterPositionManual;
    property CharacterScales: TArray<Single> read GetCharacterScales
      write SetCharacterScales;
  end;

  TMapRakuTextData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Alignment: TMapRakuTextAlignment; // 枠内の上中下と左中央右を組み合わせた配置。
    TextPathAttachment: TMapRakuTextPathAttachment; // Pathへ接触させる文字セルの面。
    Bounds: TRectF;          // 文字の組版実寸または変形後の表示範囲。
    CharacterPathOffsets: TArray<Single>; // 文字パスの標準位置からPath方向へずらす距離。
    CharacterPositionManual: TArray<Boolean>; // 手動位置を自動衝突補正から除外する文字単位フラグ。
    CharacterScales: TArray<Single>; // 文字パスの各文字へ適用する個別の均等倍率。
    FontFamily: string;      // Skiaへ渡す優先フォントファミリー。
    FontSize: Single;        // 変形前の文書座標単位フォントサイズ。
    FontStyle: TFontStyles;  // 太字、斜体、下線、取り消し線の組み合わせ。
    IndividualLetterSpacingRatios: TArray<Single>; // 各文字境界へ加える個別字間比率。
    LetterSpacingRatio: Single; // 文字サイズを1.0とする字間の加算比率。
    LineSpacingRatio: Single;   // 文字サイズを1.0とする行間の加算比率。
    Locked: Boolean;         // 編集を禁止する状態。
    Name: string;            // レイヤー一覧の表示名。
    Opacity: Single;         // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single; // 中心回りの時計回り角度。
    Text: string;            // 明示改行を含むUnicode文字列。
    TextColor: TColor;       // 本文色。基底のFillColorと同じ値を保持する。
    PaintStyle: TMapRakuPaintStyle; // 本文へ適用する共通描画スタイル。
    TransformMode: TMapRakuTextTransformMode; // 枠変形時の縦横比拘束方式。
    Visible: Boolean;        // 描画対象に含める状態。
    WrapWidth: Single;       // 入力時の折り返し幅。0は明示改行だけを使用する自動幅。
  end;

  TMapRakuRectangleLineLayer = class(TVectArtLayer)
  private
    FBounds: TRectF;
    FRotationDegrees: Single;
    FStrokeColor: TColor;
    FStrokeStyle: TVectArtMifStrokeStyle;
    FStrokeWidth: Single;
  protected
    constructor CreateWithKind(AKind: TVectArtLayerKind;
      const AName: string; const ABounds: TRectF);
  public
    constructor Create(const AName: string; const ABounds: TRectF);
    property Bounds: TRectF read FBounds write FBounds;
    property RotationDegrees: Single read FRotationDegrees write FRotationDegrees;
    property StrokeColor: TColor read FStrokeColor write FStrokeColor;
    property StrokeStyle: TVectArtMifStrokeStyle read FStrokeStyle write FStrokeStyle;
    property StrokeWidth: Single read FStrokeWidth write FStrokeWidth;
  end;

  TMapRakuRectangleLineData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Bounds: TRectF;          // 回転前の四角線へ外接する基本矩形。
    Locked: Boolean;         // 編集を禁止する状態。
    Name: string;            // レイヤー一覧の表示名。
    Opacity: Single;         // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single; // 中心回りの時計回り角度。
    StrokeColor: TColor;     // 四辺へ適用する線色。
    PaintStyle: TMapRakuPaintStyle; // 四辺へ適用する共通描画スタイル。
    StrokeStyle: TVectArtMifStrokeStyle; // 四辺へ適用する線パターン。
    StrokeWidth: Single;     // 四辺へ適用する線幅。
    Visible: Boolean;        // 描画対象に含める状態。
  end;

  TMapRakuRoundedRectangleLineLayer = class(
    TMapRakuRectangleLineLayer)
  private
    FCornerRadii: TMapRakuCornerRadii;
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      const ACornerRadii: TMapRakuCornerRadii);
    property CornerRadii: TMapRakuCornerRadii read FCornerRadii
      write FCornerRadii;
  end;

  TMapRakuRoundedRectangleLineData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Bounds: TRectF;
    CornerRadii: TMapRakuCornerRadii;
    Locked: Boolean;
    Name: string;
    Opacity: Single;
    RotationDegrees: Single;
    StrokeColor: TColor;
    PaintStyle: TMapRakuPaintStyle;
    StrokeStyle: TVectArtMifStrokeStyle;
    StrokeWidth: Single;
    Visible: Boolean;
  end;

  TMapRakuEllipseLineLayer = class(TMapRakuRectangleLineLayer)
  public
    constructor Create(const AName: string; const ABounds: TRectF);
  end;

  TMapRakuEllipseLineData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Bounds: TRectF;
    Locked: Boolean;
    Name: string;
    Opacity: Single;
    RotationDegrees: Single;
    StrokeColor: TColor;
    PaintStyle: TMapRakuPaintStyle;
    StrokeStyle: TVectArtMifStrokeStyle;
    StrokeWidth: Single;
    Visible: Boolean;
  end;

  TMapRakuArcLayer = class(TVectArtLayer)
  private
    FBounds: TRectF;
    FLineCap: TVectArtLineCap;
    FRotationDegrees: Single;
    FStartAngleDegrees: Single;
    FStrokeColor: TColor;
    FStrokeStyle: TVectArtMifStrokeStyle;
    FStrokeWidth: Single;
    FSweepAngleDegrees: Single;
  public
    constructor Create(const AName: string; const ABounds: TRectF);
    property Bounds: TRectF read FBounds write FBounds;
    property LineCap: TVectArtLineCap read FLineCap write FLineCap;
    property RotationDegrees: Single read FRotationDegrees write FRotationDegrees;
    property StartAngleDegrees: Single read FStartAngleDegrees write FStartAngleDegrees;
    property StrokeColor: TColor read FStrokeColor write FStrokeColor;
    property StrokeStyle: TVectArtMifStrokeStyle read FStrokeStyle write FStrokeStyle;
    property StrokeWidth: Single read FStrokeWidth write FStrokeWidth;
    property SweepAngleDegrees: Single read FSweepAngleDegrees write FSweepAngleDegrees;
  end;

  TMapRakuArcData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Bounds: TRectF;            // 回転前の基礎楕円へ外接する基本矩形。
    LineCap: TVectArtLineCap;  // 開いた円弧の両端形状。
    Locked: Boolean;           // 編集を禁止する状態。
    Name: string;              // レイヤー一覧の表示名。
    Opacity: Single;           // 0.0..1.0のレイヤー不透明度。
    RotationDegrees: Single;   // 基礎楕円中心回りの時計回り角度。
    StartAngleDegrees: Single; // 基礎楕円の右向きを0度とする開始角。
    StrokeColor: TColor;       // 円弧の線色。
    PaintStyle: TMapRakuPaintStyle; // 円弧へ適用する共通描画スタイル。
    StrokeStyle: TVectArtMifStrokeStyle; // 円弧の線パターン。
    StrokeWidth: Single;       // 円弧の線幅。
    SweepAngleDegrees: Single; // 開始角から時計回りへ進む角度。
    Visible: Boolean;          // 描画対象に含める状態。
  end;

  TMapRakuEllipseArcShapeLayer = class(TVectArtRectangleLayer)
  private
    FStartAngleDegrees: Single;
    FSweepAngleDegrees: Single;
  public
    constructor Create(const AName: string; const ABounds: TRectF;
      AFillColor: TColor);
    property StartAngleDegrees: Single read FStartAngleDegrees
      write FStartAngleDegrees;
    property SweepAngleDegrees: Single read FSweepAngleDegrees
      write FSweepAngleDegrees;
  end;

  TMapRakuEllipseArcShapeData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Bounds: TRectF;
    FillColor: TColor;
    PaintStyle: TMapRakuPaintStyle;
    Locked: Boolean;
    Name: string;
    Opacity: Single;
    RotationDegrees: Single;
    StartAngleDegrees: Single;
    SweepAngleDegrees: Single;
    Visible: Boolean;
  end;

  TVectArtPathLayer = class(TVectArtLayer)
  private
    FMapElement: string;
    FMapStepCount: Integer;
    FClosed: Boolean;
    FLineCap: TVectArtLineCap;
    FStrokeColor: TColor;
    FMifStrokeStyle: TVectArtMifStrokeStyle;
    FStrokeWidth: Single;
    FVertices: TArray<TMapRakuVertex>;
    FWidthPoints: TArray<TMapRakuStrokeWidthPoint>;
    function GetVertices: TArray<TMapRakuVertex>;
    function GetWidthPoints: TArray<TMapRakuStrokeWidthPoint>;
    procedure SetVertices(const Value: TArray<TMapRakuVertex>);
    procedure SetWidthPoints(
      const Value: TArray<TMapRakuStrokeWidthPoint>);
  public
    constructor Create(const AName: string;
      const AVertices: TArray<TMapRakuVertex>; AClosed: Boolean);
    function EditablePathVertices: TArray<TMapRakuVertex>; override;
    procedure AssignEditablePathVertices(
      const Value: TArray<TMapRakuVertex>); override;
    function SupportsPathEditing: Boolean; override;
    property MapElement: string read FMapElement write FMapElement; // 空文字は通常の線。road / jr / rail / river。
    property MapStepCount: Integer read FMapStepCount write FMapStepCount;
    property Closed: Boolean read FClosed write FClosed;
    property LineCap: TVectArtLineCap read FLineCap write FLineCap;
    property StrokeColor: TColor read FStrokeColor write FStrokeColor;
    property MifStrokeStyle: TVectArtMifStrokeStyle read FMifStrokeStyle
      write FMifStrokeStyle;
    property StrokeWidth: Single read FStrokeWidth write FStrokeWidth;
    property Vertices: TArray<TMapRakuVertex> read GetVertices
      write SetVertices;
    property WidthPoints: TArray<TMapRakuStrokeWidthPoint>
      read GetWidthPoints write SetWidthPoints;
  end;

  TVectArtPathData = record
    MapElement: string; // 地図経路の種類。空文字は汎用Path。
    MapStepCount: Integer; // 階段の段数。0は長さから自動決定。
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Closed: Boolean;                        // 終点と始点を閉じる状態。
    LineCap: TVectArtLineCap;               // 開いたPathの線端形状。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    StrokeColor: TColor;                    // 開いたPathの線色。
    PaintStyle: TMapRakuPaintStyle;    // Pathへ適用する共通描画スタイル。
    MifStrokeStyle: TVectArtMifStrokeStyle; // 開いたPathの線パターン。
    StrokeWidth: Single;                    // 開いたPathの線幅。
    Vertices: TArray<TMapRakuVertex>;  // 開いたPathを構成するアンカーと区間情報。
    WidthPoints: TArray<TMapRakuStrokeWidthPoint>; // 省略時は全区間が基準線幅。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TMapRakuShapeLayer = class(TVectArtLayer)
  private
    FContours: TArray<TMapRakuContour>;
    FFillColor: TColor;
    FFillRule: TMapRakuFillRule;
    FStrokeColor: TColor;
    FStrokeStyle: TVectArtMifStrokeStyle;
    FStrokeWidth: Single;
    function GetContourCount: Integer;
    function GetContours: TArray<TMapRakuContour>;
    procedure SetContours(const Value: TArray<TMapRakuContour>);
  public
    constructor Create(const AName: string;
      const AContours: TArray<TMapRakuContour>);
    property Contours: TArray<TMapRakuContour> read GetContours
      write SetContours;
    property ContourCount: Integer read GetContourCount;
    property FillColor: TColor read FFillColor write FFillColor;
    property FillRule: TMapRakuFillRule read FFillRule write FFillRule;
    property StrokeColor: TColor read FStrokeColor write FStrokeColor;
    property StrokeStyle: TVectArtMifStrokeStyle read FStrokeStyle
      write FStrokeStyle;
    property StrokeWidth: Single read FStrokeWidth write FStrokeWidth;
  end;

  TMapRakuShapeData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Contours: TArray<TMapRakuContour>; // 外周、穴、分離領域を含む閉輪郭群。
    FillColor: TColor;                      // Even-Odd等の規則で塗る色。
    PaintStyle: TMapRakuPaintStyle;    // 主となる塗りへ適用する描画スタイル。
    FillRule: TMapRakuFillRule;        // 複数輪郭の内外判定規則。
    Locked: Boolean;                        // 編集を禁止する状態。
    Name: string;                           // レイヤー一覧の表示名。
    Opacity: Single;                        // 0.0..1.0のレイヤー不透明度。
    StrokeColor: TColor;                    // 全輪郭へ適用する縁取り色。
    StrokeStyle: TVectArtMifStrokeStyle;    // 全輪郭へ適用する線パターン。
    StrokeWidth: Single;                    // 0の場合は縁取りなし。
    Visible: Boolean;                       // 描画対象に含める状態。
  end;

  TVectArtImageLayer = class(TVectArtLayer)
  private
    FPngData: TBytes;
    FPoints: TVectArtImagePoints;
    FSourceFileName: string;
    FSourceKind: TVectArtImageSourceKind;
  public
    constructor Create(const AName: string; const APngData: TBytes;
      const APoints: TVectArtImagePoints; ASourceKind: TVectArtImageSourceKind;
      const ASourceFileName: string = '');
    property PngData: TBytes read FPngData;
    property Points: TVectArtImagePoints read FPoints write FPoints;
    property SourceFileName: string read FSourceFileName;
    property SourceKind: TVectArtImageSourceKind read FSourceKind;
  end;

  TVectArtImageData = record
    Transform: TArray<Double>; // 復元時にも保持する表示変形。未設定は恒等変換。
    Locked: Boolean;                     // 編集を禁止する状態。
    Name: string;                        // レイヤー一覧の表示名。
    Opacity: Single;                     // 0.0..1.0のレイヤー不透明度。
    PngData: TBytes;                     // Skiaが読める符号化画像の全バイト。名称は旧形式互換。
    Points: TVectArtImagePoints;         // 左上から時計回りの配置4頂点。
    SourceFileName: string;              // JSONから参照する画像ファイルパス。
    SourceKind: TVectArtImageSourceKind; // MIF由来のimage／logo区分。
    Visible: Boolean;                    // 描画対象に含める状態。
  end;

  TVectArtDocument = class
  private
    FLayers: TObjectList<TVectArtLayer>;
    FCrossingRelations: TObjectList<TMapRakuCrossingRelation>;
    FChangePending: Boolean;
    FDeferredChanged: Boolean;
    FDeferredNotificationCount: Integer;
    FInteractiveChanged: Boolean;
    FInteractiveUpdateCount: Integer;
    FOnChanged: TNotifyEvent;
    FRevision: Int64;
    FSelectedIndex: Integer;
    FSelectedLayers: TList<Integer>;
    FUpdateCount: Integer;
    function GetCanvasLayer: TVectArtCanvasLayer;
    function GetCrossingRelationCount: Integer;
    function GetLayer(Index: Integer): TVectArtLayer;
    function GetLayerCount: Integer;
    function GetIsInteractiveUpdate: Boolean;
    function GetSelectionCount: Integer;
    function GetCrossingRelation(Index: Integer): TMapRakuCrossingRelation;
    procedure SelectionChanged;
    procedure SetSelectedLayersCore(const Indices: array of Integer;
      Notify: Boolean);
    procedure SetSelectedIndex(const Value: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginInteractiveUpdate;
    // 高頻度操作中の変更通知だけをまとめ、RevisionとDocument内容は即時更新する。
    procedure BeginDeferredNotification;
    procedure BeginUpdate;
    procedure Changed;
    procedure EndInteractiveUpdate;
    // 対応する開始以降に変更があれば、最後にOnChangedを1回だけ呼ぶ。
    procedure EndDeferredNotification;
    procedure EndUpdate;
    function GetSelectedLayerIndices: TArray<Integer>;
    function FindCrossingRelation(const ObjectAId, ObjectBId: string):
      TMapRakuCrossingRelation;
    procedure SetCrossingRelation(const ObjectAId, ObjectBId: string;
      Kind: TMapRakuCrossingKind; const UpperObjectId: string;
      RangeMargin: Single = 12);
    procedure ClearCrossingRelations;
    procedure RemoveCrossingRelation(const ObjectAId, ObjectBId: string);
    // 所有権を呼び出し側へ移し、レイヤーデータを破棄せずDocumentから取り外す。
    function ExtractLayer(Index: Integer): TVectArtLayer;
    // 呼び出し側から所有権を受け取り、既存レイヤーを指定積層位置へ挿入する。
    function InsertLayer(Index: Integer; Layer: TVectArtLayer): Integer;
    function InsertRectangle(Index: Integer;
      const Data: TVectArtRectangleData): Integer;
    // 角丸半径と回転を含む角丸四角を指定位置へ挿入し、実際のレイヤー番号を返す。
    function InsertRoundedRectangle(Index: Integer;
      const Data: TMapRakuRoundedRectangleData): Integer;
    // 塗りと回転を持つ楕円を指定位置へ挿入し、実際のレイヤー番号を返す。
    function InsertEllipse(Index: Integer;
      const Data: TMapRakuEllipseData): Integer;
    function InsertRectangleLine(Index: Integer;
      const Data: TMapRakuRectangleLineData): Integer;
    function InsertRoundedRectangleLine(Index: Integer;
      const Data: TMapRakuRoundedRectangleLineData): Integer;
    function InsertEllipseLine(Index: Integer;
      const Data: TMapRakuEllipseLineData): Integer;
    // 基礎楕円と角度、線属性を持つ円弧を指定位置へ挿入する。
    function InsertArc(Index: Integer;
      const Data: TMapRakuArcData): Integer;
    function InsertEllipseArcShape(Index: Integer;
      const Data: TMapRakuEllipseArcShapeData): Integer;
    function InsertPath(Index: Integer; const Data: TVectArtPathData): Integer;
    // 複数の閉輪郭を持つShapeを指定位置へ挿入し、実際のレイヤー番号を返す。
    function InsertShape(Index: Integer;
      const Data: TMapRakuShapeData): Integer;
    function InsertImage(Index: Integer; const Data: TVectArtImageData): Integer;
    function InsertText(Index: Integer; const Data: TMapRakuTextData): Integer;
    function IsLayerSelected(Index: Integer): Boolean;
    procedure SetCanvasSize(AWidth, AHeight: Integer);
    procedure SetRectangleBounds(Index: Integer; const Value: TRectF);
    procedure SetRectangleFillColor(Index: Integer; Value: TColor);
    procedure SetRectangleRotation(Index: Integer; Value: Single);
    procedure SetRectangleLineBounds(Index: Integer; const Value: TRectF);
    procedure SetRectangleLineRotation(Index: Integer; Value: Single);
    procedure SetRectangleLineStroke(Index: Integer; Color: TColor;
      Width: Single; Style: TVectArtMifStrokeStyle);
    procedure SetRoundedRectangleLineCornerRadii(Index: Integer;
      const Value: TMapRakuCornerRadii);
    procedure SetArcBounds(Index: Integer; const Value: TRectF);
    procedure SetArcAngles(Index: Integer; StartAngleDegrees,
      SweepAngleDegrees: Single);
    procedure SetArcLineCap(Index: Integer; Value: TVectArtLineCap);
    procedure SetArcRotation(Index: Integer; Value: Single);
    procedure SetArcStroke(Index: Integer; Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
    procedure SetEllipseArcShapeAngles(Index: Integer; StartAngleDegrees,
      SweepAngleDegrees: Single);
    // 角丸四角の各隅半径を辺内へ収まる値に制限して更新する。
    procedure SetRoundedRectangleCornerRadii(Index: Integer;
      const Value: TMapRakuCornerRadii);
    procedure SetImagePoints(Index: Integer;
      const Points: TVectArtImagePoints);
    procedure SetTextData(Index: Integer; const Data: TMapRakuTextData);
    // Document内またはグループ内の既存文字へ全永続属性を適用し、変更を通知する。
    procedure SetTextLayerData(Layer: TMapRakuTextLayer;
      const Data: TMapRakuTextData);
    procedure SetPathLineCap(Index: Integer; Value: TVectArtLineCap);
    procedure SetLayerLocked(Index: Integer; Value: Boolean);
    procedure SetLayerOpacity(Index: Integer; Value: Single);
    procedure SetLayerVisible(Index: Integer; Value: Boolean);
    procedure MoveLayer(FromIndex, ToIndex: Integer);
    function RemoveRectangle(Index: Integer;
      out Data: TVectArtRectangleData): Boolean;
    // 角丸四角を削除し、Undoで型と全属性を復元できるデータを返す。
    function RemoveRoundedRectangle(Index: Integer;
      out Data: TMapRakuRoundedRectangleData): Boolean;
    function RemoveEllipse(Index: Integer;
      out Data: TMapRakuEllipseData): Boolean;
    function RemoveRectangleLine(Index: Integer;
      out Data: TMapRakuRectangleLineData): Boolean;
    function RemoveRoundedRectangleLine(Index: Integer;
      out Data: TMapRakuRoundedRectangleLineData): Boolean;
    function RemoveEllipseLine(Index: Integer;
      out Data: TMapRakuEllipseLineData): Boolean;
    function RemoveArc(Index: Integer; out Data: TMapRakuArcData): Boolean;
    function RemoveEllipseArcShape(Index: Integer;
      out Data: TMapRakuEllipseArcShapeData): Boolean;
    function RemovePath(Index: Integer; out Data: TVectArtPathData): Boolean;
    // Shapeを削除し、Undo用の独立したデータをDataへ返す。
    function RemoveShape(Index: Integer;
      out Data: TMapRakuShapeData): Boolean;
    function RemoveImage(Index: Integer; out Data: TVectArtImageData): Boolean;
    function RemoveText(Index: Integer; out Data: TMapRakuTextData): Boolean;
    // Pathのアンカー、制御点、区間種別を深いコピーで置換する。
    procedure SetPathVertices(Index: Integer;
      const Vertices: TArray<TMapRakuVertex>);
    procedure SetPathWidthPoints(Index: Integer;
      const WidthPoints: TArray<TMapRakuStrokeWidthPoint>);
    procedure SetPathStroke(Index: Integer; Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
    // Shapeの輪郭群を深いコピーで置換し、Document変更を通知する。
    procedure SetShapeContours(Index: Integer;
      const Contours: TArray<TMapRakuContour>);
    // Shapeの塗り色と複数輪郭の内外判定規則を更新する。
    procedure SetShapeFill(Index: Integer; Color: TColor;
      FillRule: TMapRakuFillRule);
    // Shapeの全輪郭へ共通適用する縁取り設定を更新する。
    procedure SetShapeStroke(Index: Integer; Color: TColor; Width: Single;
      Style: TVectArtMifStrokeStyle);
    procedure SelectLayerRange(AnchorIndex, TargetIndex: Integer;
      Additive: Boolean);
    procedure SetSelectedLayers(const Indices: array of Integer);
    procedure ToggleSelectedLayer(Index: Integer);
    property CanvasLayer: TVectArtCanvasLayer read GetCanvasLayer;
    property CrossingRelationCount: Integer read GetCrossingRelationCount;
    property CrossingRelations[Index: Integer]: TMapRakuCrossingRelation
      read GetCrossingRelation;
    property LayerCount: Integer read GetLayerCount;
    property Layers[Index: Integer]: TVectArtLayer read GetLayer; default;
    property IsInteractiveUpdate: Boolean read GetIsInteractiveUpdate;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property Revision: Int64 read FRevision;
    property SelectedIndex: Integer read FSelectedIndex write SetSelectedIndex;
    property SelectionCount: Integer read GetSelectionCount;
  end;

const
  DEFAULT_CANVAS_WIDTH = 1920;
  DEFAULT_CANVAS_HEIGHT = 1080;
  // 旧実装名はMIF style 3（ダッシュ・ドット）として互換維持する。
  vssDashed: TVectArtMifStrokeStyle = vssDashDot;

function VectArtStrokeDashIntervals(Style: TVectArtMifStrokeStyle;
  Width: Single): TArray<Single>;
function VectArtStrokeUsesRoundCaps(Style: TVectArtMifStrokeStyle): Boolean;
// 見た目を変えずにPathを可変幅へ切り替える両端100%の幅点を返す。
function UniformMapRakuStrokeWidthPoints:
  TArray<TMapRakuStrokeWidthPoint>;
// 文字パスへ渡す文字列を改行を含まない単一行へ正規化する。
function NormalizeMapRakuTextPathText(const Value: string): string;
// 4隅へ同じ半径を設定した角丸値を返す。
function UniformMapRakuCornerRadii(Radius: Single): TMapRakuCornerRadii;
// 各辺で隣接半径が重ならない比率へ角丸値を縮小する。
function ClampMapRakuCornerRadii(const Bounds: TRectF;
  const Value: TMapRakuCornerRadii): TMapRakuCornerRadii;

implementation

uses
  System.Math, MapRakuEllipseGeometry, MapRakuGeometry;

{ TMapRakuGroupLayer }

constructor TMapRakuLevelBoundaryLayer.Create(const AName:string);
begin
  inherited Create(vlkMapLevelBoundary,AName);
  Locked:=False; Visible:=True;
end;

procedure TMapRakuGroupLayer.AddChild(Layer: TVectArtLayer);
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  FChildren.Add(Layer);
end;

constructor TMapRakuGroupLayer.Create(const AName: string);
begin
  inherited Create(vlkGroup, AName);
  FChildren := TObjectList<TVectArtLayer>.Create(True);
end;

destructor TMapRakuGroupLayer.Destroy;
begin
  FChildren.Free;
  inherited Destroy;
end;

function TMapRakuGroupLayer.ExtractChild(Index: Integer): TVectArtLayer;
begin
  Result := FChildren.Extract(FChildren[Index]);
end;

function TMapRakuGroupLayer.GetChild(Index: Integer): TVectArtLayer;
begin
  Result := FChildren[Index];
end;

function TMapRakuGroupLayer.GetChildCount: Integer;
begin
  Result := FChildren.Count;
end;

procedure TMapRakuGroupLayer.InsertChild(Index: Integer;
  Layer: TVectArtLayer);
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  FChildren.Insert(EnsureRange(Index, 0, FChildren.Count), Layer);
end;

function UniformMapRakuStrokeWidthPoints:
  TArray<TMapRakuStrokeWidthPoint>;
begin
  SetLength(Result, 2);
  Result[0].Offset := 0;
  Result[0].LeftScale := 1;
  Result[0].RightScale := 1;
  Result[1].Offset := 1;
  Result[1].LeftScale := 1;
  Result[1].RightScale := 1;
end;

function UniformMapRakuCornerRadii(
  Radius: Single): TMapRakuCornerRadii;
begin
  Radius := Max(Radius, 0.0);
  Result.TopLeft := Radius;
  Result.TopRight := Radius;
  Result.BottomRight := Radius;
  Result.BottomLeft := Radius;
end;

function ClampMapRakuCornerRadii(const Bounds: TRectF;
  const Value: TMapRakuCornerRadii): TMapRakuCornerRadii;
var
  Height: Single;
  Scale: Single;
  Sum: Single;
  Width: Single;
begin
  Result.TopLeft := Max(Value.TopLeft, 0.0);
  Result.TopRight := Max(Value.TopRight, 0.0);
  Result.BottomRight := Max(Value.BottomRight, 0.0);
  Result.BottomLeft := Max(Value.BottomLeft, 0.0);
  Width := Max(Bounds.Width, 0.0);
  Height := Max(Bounds.Height, 0.0);
  Scale := 1.0;
  Sum := Result.TopLeft + Result.TopRight;
  if Sum > 0 then
    Scale := Min(Scale, Width / Sum);
  Sum := Result.BottomLeft + Result.BottomRight;
  if Sum > 0 then
    Scale := Min(Scale, Width / Sum);
  Sum := Result.TopLeft + Result.BottomLeft;
  if Sum > 0 then
    Scale := Min(Scale, Height / Sum);
  Sum := Result.TopRight + Result.BottomRight;
  if Sum > 0 then
    Scale := Min(Scale, Height / Sum);
  if Scale < 1.0 then
  begin
    Result.TopLeft := Result.TopLeft * Scale;
    Result.TopRight := Result.TopRight * Scale;
    Result.BottomRight := Result.BottomRight * Scale;
    Result.BottomLeft := Result.BottomLeft * Scale;
  end;
end;

function CopyShapeContours(
  const Source: TArray<TMapRakuContour>): TArray<TMapRakuContour>;
var
  I: Integer;
begin
  SetLength(Result, Length(Source));
  for I := 0 to High(Source) do
    Result[I].Vertices := Copy(Source[I].Vertices);
end;

procedure ValidateShapeContours(
  const Contours: TArray<TMapRakuContour>);
var
  I: Integer;
begin
  if Length(Contours) = 0 then
    raise EArgumentException.Create('Shape must contain at least one contour');
  for I := 0 to High(Contours) do
    if Length(Contours[I].Vertices) < 3 then
      raise EArgumentException.CreateFmt(
        'Shape contour %d must contain at least three vertices', [I]);
end;

function ShapeContoursEqual(const Left,
  Right: TArray<TMapRakuContour>): Boolean;
var
  ContourIndex: Integer;
  VertexIndex: Integer;
begin
  if Length(Left) <> Length(Right) then
    Exit(False);
  for ContourIndex := 0 to High(Left) do
  begin
    if Length(Left[ContourIndex].Vertices) <>
      Length(Right[ContourIndex].Vertices) then
      Exit(False);
    for VertexIndex := 0 to High(Left[ContourIndex].Vertices) do
      with Left[ContourIndex].Vertices[VertexIndex] do
      begin
        if not SameValue(Position.X,
          Right[ContourIndex].Vertices[VertexIndex].Position.X) or
          not SameValue(Position.Y,
          Right[ContourIndex].Vertices[VertexIndex].Position.Y) or
          not SameValue(IncomingControl.X,
          Right[ContourIndex].Vertices[VertexIndex].IncomingControl.X) or
          not SameValue(IncomingControl.Y,
          Right[ContourIndex].Vertices[VertexIndex].IncomingControl.Y) or
          not SameValue(OutgoingControl.X,
          Right[ContourIndex].Vertices[VertexIndex].OutgoingControl.X) or
          not SameValue(OutgoingControl.Y,
          Right[ContourIndex].Vertices[VertexIndex].OutgoingControl.Y) or
          (OutgoingSegment <>
          Right[ContourIndex].Vertices[VertexIndex].OutgoingSegment) or
          (Kind <> Right[ContourIndex].Vertices[VertexIndex].Kind) then
          Exit(False);
      end;
  end;
  Result := True;
end;

{ TMapRakuContour }

function TMapRakuContour.SegmentCount: Integer;
begin
  Result := Length(Vertices);
end;

function VectArtStrokeDashIntervals(Style: TVectArtMifStrokeStyle;
  Width: Single): TArray<Single>;
begin
  Width := Max(Width, 0.1);
  case Style of
    vssDotted:
      Result := [Width, Width * 2];
    vssShortDash:
      Result := [Width * 3, Width * 3];
    vssDashDot:
      Result := [Width * 6, Width * 2, Width, Width * 2];
    vssDashDotDot:
      Result := [Width * 6, Width * 2, Width, Width * 2,
        Width, Width * 2];
    vssSparseDotted:
      Result := [Width, Width * 4];
    vssMediumDash:
      Result := [Width * 5, Width * 2];
    vssLongDashDot:
      Result := [Width * 9, Width * 2, Width, Width * 2];
    vssLongDash:
      Result := [Width * 9, Width * 3];
  else
    Result := nil;
  end;
end;

function VectArtStrokeUsesRoundCaps(Style: TVectArtMifStrokeStyle): Boolean;
begin
  Result := Style in [vssDotted, vssDashDot, vssDashDotDot,
    vssSparseDotted, vssLongDashDot];
end;

{ TVectArtLayer }

constructor TVectArtLayer.Create(AKind: TVectArtLayerKind;
  const AName: string);
var
  Id: TGUID;
begin
  inherited Create;
  CreateGUID(Id);
  FPersistentId := GUIDToString(Id);
  FFilters := TObjectList<TMapRakuFilter>.Create(True);
  FTransform := TMapRakuTransform.Identity;
  FKind := AKind;
  FLocked := False;
  FName := AName;
  FOpacity := 1.0;
  FPaintStyle := TMapRakuPaintStyle.Solid(clBlack);
  FVisible := True;
end;

procedure TVectArtLayer.AddFilter(Filter: TMapRakuFilter);
begin
  if Filter = nil then
    raise EArgumentNilException.Create('Filter');
  FFilters.Add(Filter);
end;

procedure TVectArtLayer.ClearFilters;
begin
  FFilters.Clear;
end;

procedure TVectArtLayer.DeleteFilter(Index: Integer);
begin
  FFilters.Delete(Index);
end;

destructor TVectArtLayer.Destroy;
begin
  FFilters.Free;
  inherited Destroy;
end;

function TVectArtLayer.ExtractFilter(Index: Integer): TMapRakuFilter;
begin
  Result := FFilters.Extract(FFilters[Index]);
end;

function TVectArtLayer.GetFilter(Index: Integer): TMapRakuFilter;
begin
  Result := FFilters[Index];
end;

function TVectArtLayer.GetFilterCount: Integer;
begin
  Result := FFilters.Count;
end;

procedure TVectArtLayer.InsertFilter(Index: Integer;
  Filter: TMapRakuFilter);
begin
  if Filter = nil then
    raise EArgumentNilException.Create('Filter');
  FFilters.Insert(EnsureRange(Index, 0, FFilters.Count), Filter);
end;

procedure TVectArtLayer.MoveFilter(FromIndex, ToIndex: Integer);
begin
  FFilters.Move(FromIndex, EnsureRange(ToIndex, 0, FFilters.Count - 1));
end;

function TVectArtLayer.EditablePathVertices: TArray<TMapRakuVertex>;
begin
  Result := nil;
end;

procedure TVectArtLayer.AssignEditablePathVertices(
  const Value: TArray<TMapRakuVertex>);
begin
end;

function TVectArtLayer.SupportsPathEditing: Boolean;
begin
  Result := False;
end;

{ TVectArtCanvasLayer }

constructor TVectArtCanvasLayer.Create(AWidth, AHeight: Integer;
  AColor: TColor);
begin
  inherited Create(vlkCanvas, 'Canvas');
  FWidth := Max(AWidth, 1);
  FHeight := Max(AHeight, 1);
  FBackgroundColor := AColor;
  FTransparent := False;
end;

{ TVectArtRectangleLayer }

constructor TVectArtRectangleLayer.Create(const AName: string;
  const ABounds: TRectF; AFillColor: TColor);
begin
  inherited Create(vlkRectangle, AName);
  FBounds := ABounds;
  FFillColor := AFillColor;
  FRotationDegrees := 0.0;
end;

constructor TVectArtRectangleLayer.CreateWithKind(AKind: TVectArtLayerKind;
  const AName: string; const ABounds: TRectF; AFillColor: TColor);
begin
  inherited Create(AKind, AName);
  FBounds := ABounds;
  FFillColor := AFillColor;
  FRotationDegrees := 0.0;
end;

{ TMapRakuRoundedRectangleLayer }

constructor TMapRakuRoundedRectangleLayer.Create(const AName: string;
  const ABounds: TRectF; AFillColor: TColor;
  const ACornerRadii: TMapRakuCornerRadii);
begin
  inherited CreateWithKind(vlkRoundedRectangle, AName, ABounds, AFillColor);
  FCornerRadii := ClampMapRakuCornerRadii(ABounds, ACornerRadii);
end;

{ TMapRakuEllipseLayer }

constructor TMapRakuEllipseLayer.Create(const AName: string;
  const ABounds: TRectF; AFillColor: TColor);
begin
  inherited CreateWithKind(vlkEllipse, AName, ABounds, AFillColor);
end;

{ TMapRakuTextLayer }

constructor TMapRakuTextLayer.Create(const AName: string;
  const ABounds: TRectF; const AText, AFontFamily: string;
  AFontSize, AWrapWidth: Single; ATextColor: TColor);
begin
  CreateWithKind(vlkText, AName, ABounds, AText, AFontFamily, AFontSize,
    AWrapWidth, ATextColor);
end;

constructor TMapRakuTextLayer.CreateWithKind(AKind: TVectArtLayerKind;
  const AName: string; const ABounds: TRectF;
  const AText, AFontFamily: string; AFontSize, AWrapWidth: Single;
  ATextColor: TColor);
begin
  inherited CreateWithKind(AKind, AName, ABounds, ATextColor);
  FText := AText;
  FFontFamily := AFontFamily;
  FFontSize := Max(AFontSize, 1.0);
  FTransformMode := slttmUniformScale;
  FWrapWidth := Max(AWrapWidth, 0.0);
end;

procedure TMapRakuTextLayer.SetLetterSpacingRatio(Value: Single);
begin
  FLetterSpacingRatio := EnsureRange(Value,
    SCREEN_LAYOUT_TEXT_LETTER_SPACING_MIN,
    SCREEN_LAYOUT_TEXT_LETTER_SPACING_MAX);
end;

function TMapRakuTextLayer.GetIndividualLetterSpacingRatios:
  TArray<Single>;
begin
  Result := Copy(FIndividualLetterSpacingRatios);
end;

procedure TMapRakuTextLayer.SetIndividualLetterSpacingRatios(
  const Value: TArray<Single>);
var
  I: Integer;
begin
  SetLength(FIndividualLetterSpacingRatios, Length(Value));
  for I := 0 to High(Value) do
    FIndividualLetterSpacingRatios[I] := EnsureRange(Value[I],
      SCREEN_LAYOUT_TEXT_LETTER_SPACING_MIN,
      SCREEN_LAYOUT_TEXT_LETTER_SPACING_MAX);
end;

procedure TMapRakuTextLayer.SetLineSpacingRatio(Value: Single);
begin
  FLineSpacingRatio := EnsureRange(Value,
    SCREEN_LAYOUT_TEXT_LINE_SPACING_MIN,
    SCREEN_LAYOUT_TEXT_LINE_SPACING_MAX);
end;

procedure TMapRakuTextLayer.SetText(const Value: string);
begin
  if FText <> Value then
    SetLength(FIndividualLetterSpacingRatios, 0);
  FText := Value;
end;

function NormalizeMapRakuTextPathText(const Value: string): string;
begin
  Result := StringReplace(Value, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

{ TMapRakuTextPathLayer }

constructor TMapRakuTextPathLayer.Create(const AName: string;
  const ABounds: TRectF; const AText, AFontFamily: string;
  AFontSize, AWrapWidth: Single; ATextColor: TColor;
  const AVertices: TArray<TMapRakuVertex>);
begin
  inherited CreateWithKind(vlkTextPath, AName, ABounds, AText, AFontFamily,
    AFontSize, AWrapWidth, ATextColor);
  FAttachment := sltpaBottom;
  LetterSpacingRatio := 0;
  IndividualLetterSpacingRatios := nil;
  CharacterPathOffsets := nil;
  CharacterPositionManual := nil;
  CharacterScales := nil;
  WrapWidth := 0;
  SetText(AText);
  AssignEditablePathVertices(AVertices);
end;

procedure TMapRakuTextPathLayer.SetText(const Value: string);
var
  NormalizedValue: string;
begin
  NormalizedValue := NormalizeMapRakuTextPathText(Value);
  if Text <> NormalizedValue then
  begin
    SetLength(FCharacterPathOffsets, 0);
    SetLength(FCharacterPositionManual, 0);
    SetLength(FCharacterScales, 0);
  end;
  inherited SetText(NormalizedValue);
end;

function TMapRakuTextPathLayer.GetCharacterPathOffsets:
  TArray<Single>;
begin
  Result := Copy(FCharacterPathOffsets);
end;

function TMapRakuTextPathLayer.GetCharacterScales: TArray<Single>;
begin
  Result := Copy(FCharacterScales);
end;

function TMapRakuTextPathLayer.GetCharacterPositionManual:
  TArray<Boolean>;
begin
  Result := Copy(FCharacterPositionManual);
end;

procedure TMapRakuTextPathLayer.SetCharacterPathOffsets(
  const Value: TArray<Single>);
begin
  FCharacterPathOffsets := Copy(Value);
end;

procedure TMapRakuTextPathLayer.SetCharacterPositionManual(
  const Value: TArray<Boolean>);
begin
  FCharacterPositionManual := Copy(Value);
end;

procedure TMapRakuTextPathLayer.SetCharacterScales(
  const Value: TArray<Single>);
var
  I: Integer;
begin
  SetLength(FCharacterScales, Length(Value));
  for I := 0 to High(Value) do
    FCharacterScales[I] := EnsureRange(Value[I],
      SCREEN_LAYOUT_TEXT_PATH_CHARACTER_SCALE_MIN,
      SCREEN_LAYOUT_TEXT_PATH_CHARACTER_SCALE_MAX);
end;

function TMapRakuTextPathLayer.EditablePathVertices:
  TArray<TMapRakuVertex>;
begin
  Result := Copy(FVertices);
end;

procedure TMapRakuTextPathLayer.AssignEditablePathVertices(
  const Value: TArray<TMapRakuVertex>);
begin
  FVertices := Copy(Value);
end;

function TMapRakuTextPathLayer.SupportsPathEditing: Boolean;
begin
  Result := True;
end;

{ TMapRakuRectangleLineLayer }

constructor TMapRakuRectangleLineLayer.Create(const AName: string;
  const ABounds: TRectF);
begin
  CreateWithKind(vlkRectangleLine, AName, ABounds);
end;

constructor TMapRakuRectangleLineLayer.CreateWithKind(
  AKind: TVectArtLayerKind; const AName: string; const ABounds: TRectF);
begin
  inherited Create(AKind, AName);
  FBounds := ABounds;
  FRotationDegrees := 0.0;
  FStrokeColor := clBlack;
  FStrokeStyle := vssSolid;
  FStrokeWidth := 1.0;
end;

{ TMapRakuRoundedRectangleLineLayer }

constructor TMapRakuRoundedRectangleLineLayer.Create(
  const AName: string; const ABounds: TRectF;
  const ACornerRadii: TMapRakuCornerRadii);
begin
  inherited CreateWithKind(vlkRoundedRectangleLine, AName, ABounds);
  FCornerRadii := ClampMapRakuCornerRadii(ABounds, ACornerRadii);
end;

{ TMapRakuEllipseLineLayer }

constructor TMapRakuEllipseLineLayer.Create(const AName: string;
  const ABounds: TRectF);
begin
  inherited CreateWithKind(vlkEllipseLine, AName, ABounds);
end;

{ TMapRakuArcLayer }

constructor TMapRakuArcLayer.Create(const AName: string;
  const ABounds: TRectF);
begin
  inherited Create(vlkArc, AName);
  FBounds := ABounds;
  FLineCap := vlcSquare;
  FRotationDegrees := 0.0;
  FStartAngleDegrees := 180.0;
  FStrokeColor := clBlack;
  FStrokeStyle := vssSolid;
  FStrokeWidth := 1.0;
  FSweepAngleDegrees := 180.0;
end;

{ TMapRakuEllipseArcShapeLayer }

constructor TMapRakuEllipseArcShapeLayer.Create(const AName: string;
  const ABounds: TRectF; AFillColor: TColor);
begin
  inherited CreateWithKind(vlkEllipseArcShape, AName, ABounds, AFillColor);
  FStartAngleDegrees := 180.0;
  FSweepAngleDegrees := 180.0;
end;

{ TVectArtPathLayer }

constructor TVectArtPathLayer.Create(const AName: string;
  const AVertices: TArray<TMapRakuVertex>; AClosed: Boolean);
begin
  inherited Create(vlkPath, AName);
  SetVertices(AVertices);
  FClosed := AClosed;
  FLineCap := vlcSquare;
  FStrokeColor := clBlack;
  FMifStrokeStyle := vssSolid;
  FStrokeWidth := 1.0;
end;

function TVectArtPathLayer.GetVertices: TArray<TMapRakuVertex>;
begin
  Result := Copy(FVertices);
end;

function TVectArtPathLayer.GetWidthPoints:
  TArray<TMapRakuStrokeWidthPoint>;
begin
  Result := Copy(FWidthPoints);
end;

procedure TVectArtPathLayer.SetVertices(
  const Value: TArray<TMapRakuVertex>);
begin
  FVertices := Copy(Value);
end;

procedure TVectArtPathLayer.SetWidthPoints(
  const Value: TArray<TMapRakuStrokeWidthPoint>);
begin
  FWidthPoints := Copy(Value);
end;

function TVectArtPathLayer.EditablePathVertices:
  TArray<TMapRakuVertex>;
begin
  Result := Vertices;
end;

procedure TVectArtPathLayer.AssignEditablePathVertices(
  const Value: TArray<TMapRakuVertex>);
begin
  Vertices := Value;
end;

function TVectArtPathLayer.SupportsPathEditing: Boolean;
begin
  Result := True;
end;

{ TMapRakuShapeLayer }

constructor TMapRakuShapeLayer.Create(const AName: string;
  const AContours: TArray<TMapRakuContour>);
begin
  inherited Create(vlkShape, AName);
  SetContours(AContours);
  FFillColor := clWhite;
  FFillRule := slfrEvenOdd;
  FStrokeColor := clBlack;
  FStrokeStyle := vssSolid;
  FStrokeWidth := 0.0;
end;

function TMapRakuShapeLayer.GetContours: TArray<TMapRakuContour>;
begin
  Result := CopyShapeContours(FContours);
end;

function TMapRakuShapeLayer.GetContourCount: Integer;
begin
  Result := Length(FContours);
end;

procedure TMapRakuShapeLayer.SetContours(
  const Value: TArray<TMapRakuContour>);
begin
  ValidateShapeContours(Value);
  FContours := CopyShapeContours(Value);
end;

{ TVectArtImageLayer }

constructor TVectArtImageLayer.Create(const AName: string;
  const APngData: TBytes; const APoints: TVectArtImagePoints;
  ASourceKind: TVectArtImageSourceKind; const ASourceFileName: string);
begin
  inherited Create(vlkImage, AName);
  FPngData := Copy(APngData);
  FPoints := APoints;
  FSourceFileName := ASourceFileName;
  FSourceKind := ASourceKind;
end;

{ TVectArtDocument }

constructor TVectArtDocument.Create;
begin
  inherited Create;
  FLayers := TObjectList<TVectArtLayer>.Create(True);
  FCrossingRelations := TObjectList<TMapRakuCrossingRelation>.Create(True);
  FSelectedLayers := TList<Integer>.Create;
  FLayers.Add(TVectArtCanvasLayer.Create(DEFAULT_CANVAS_WIDTH,
    DEFAULT_CANVAS_HEIGHT, clWhite));
  FSelectedIndex := -1;
end;

destructor TVectArtDocument.Destroy;
begin
  FCrossingRelations.Free;
  FSelectedLayers.Free;
  FLayers.Free;
  inherited Destroy;
end;

function TVectArtDocument.GetCrossingRelationCount: Integer;
begin
  Result := FCrossingRelations.Count;
end;

function TVectArtDocument.GetCrossingRelation(
  Index: Integer): TMapRakuCrossingRelation;
begin
  Result := FCrossingRelations[Index];
end;

function TVectArtDocument.FindCrossingRelation(const ObjectAId,
  ObjectBId: string): TMapRakuCrossingRelation;
var R: TMapRakuCrossingRelation;
begin
  for R in FCrossingRelations do
    if ((R.ObjectAId=ObjectAId) and (R.ObjectBId=ObjectBId)) or
      ((R.ObjectAId=ObjectBId) and (R.ObjectBId=ObjectAId)) then Exit(R);
  Result := nil;
end;

procedure TVectArtDocument.SetCrossingRelation(const ObjectAId,
  ObjectBId: string; Kind: TMapRakuCrossingKind;
  const UpperObjectId: string; RangeMargin: Single);
var R: TMapRakuCrossingRelation;
begin
  if (ObjectAId='') or (ObjectBId='') or (ObjectAId=ObjectBId) then Exit;
  R := FindCrossingRelation(ObjectAId,ObjectBId);
  if R=nil then
  begin
    R:=TMapRakuCrossingRelation.Create;
    R.ObjectAId:=ObjectAId; R.ObjectBId:=ObjectBId;
    FCrossingRelations.Add(R);
  end;
  R.Kind:=Kind; R.UpperObjectId:=UpperObjectId;
  R.RangeMargin:=Max(RangeMargin,0); Changed;
end;

procedure TVectArtDocument.ClearCrossingRelations;
begin
  if FCrossingRelations.Count=0 then Exit;
  FCrossingRelations.Clear; Changed;
end;

procedure TVectArtDocument.RemoveCrossingRelation(const ObjectAId,
  ObjectBId: string);
var I:Integer; R:TMapRakuCrossingRelation;
begin
  for I:=FCrossingRelations.Count-1 downto 0 do
  begin
    R:=FCrossingRelations[I];
    if ((R.ObjectAId=ObjectAId) and (R.ObjectBId=ObjectBId)) or
      ((R.ObjectAId=ObjectBId) and (R.ObjectBId=ObjectAId)) then
    begin FCrossingRelations.Delete(I); Changed; Exit; end;
  end;
end;

procedure TVectArtDocument.Changed;
begin
  if FUpdateCount > 0 then
  begin
    FChangePending := True;
    Exit;
  end;
  Inc(FRevision);
  if FDeferredNotificationCount > 0 then
  begin
    FDeferredChanged := True;
    Exit;
  end;
  if FInteractiveUpdateCount > 0 then
    FInteractiveChanged := True;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TVectArtDocument.BeginDeferredNotification;
begin
  Inc(FDeferredNotificationCount);
end;

procedure TVectArtDocument.BeginInteractiveUpdate;
begin
  Inc(FInteractiveUpdateCount);
end;

procedure TVectArtDocument.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TVectArtDocument.EndInteractiveUpdate;
begin
  if FInteractiveUpdateCount <= 0 then
    Exit;
  Dec(FInteractiveUpdateCount);
  if (FInteractiveUpdateCount = 0) and FInteractiveChanged then
  begin
    FInteractiveChanged := False;
    if Assigned(FOnChanged) then
      FOnChanged(Self);
  end;
end;

procedure TVectArtDocument.EndDeferredNotification;
begin
  if FDeferredNotificationCount <= 0 then
    Exit;
  Dec(FDeferredNotificationCount);
  if (FDeferredNotificationCount = 0) and FDeferredChanged then
  begin
    FDeferredChanged := False;
    if Assigned(FOnChanged) then
      FOnChanged(Self);
  end;
end;

procedure TVectArtDocument.EndUpdate;
begin
  if FUpdateCount <= 0 then
    Exit;
  Dec(FUpdateCount);
  if (FUpdateCount = 0) and FChangePending then
  begin
    FChangePending := False;
    Changed;
  end;
end;

procedure TVectArtDocument.SelectionChanged;
begin
  if FDeferredNotificationCount > 0 then
  begin
    FDeferredChanged := True;
    Exit;
  end;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TVectArtDocument.GetSelectedLayerIndices: TArray<Integer>;
begin
  Result := FSelectedLayers.ToArray;
end;

function TVectArtDocument.ExtractLayer(Index: Integer): TVectArtLayer;
var
  I: Integer;
  Selection: TList<Integer>;
begin
  if (Index <= 0) or (Index >= FLayers.Count) then
    raise EArgumentOutOfRangeException.Create('Index');
  Result := FLayers.Extract(FLayers[Index]);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.InsertLayer(Index: Integer;
  Layer: TVectArtLayer): Integer;
var
  I: Integer;
  Selection: TArray<Integer>;
begin
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  Result := EnsureRange(Index, 1, FLayers.Count);
  Selection := FSelectedLayers.ToArray;
  FLayers.Insert(Result, Layer);
  for I := 0 to High(Selection) do
    if Selection[I] >= Result then
      Inc(Selection[I]);
  SetSelectedLayersCore(Selection, False);
  Changed;
end;

function TVectArtDocument.GetIsInteractiveUpdate: Boolean;
begin
  Result := FInteractiveUpdateCount > 0;
end;

function TVectArtDocument.InsertRectangle(Index: Integer;
  const Data: TVectArtRectangleData): Integer;
var
  I: Integer;
  RectangleLayer: TVectArtRectangleLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  RectangleLayer := TVectArtRectangleLayer.Create(Data.Name, Data.Bounds,
    Data.FillColor);
  RectangleLayer.Locked := Data.Locked;
  RectangleLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  RectangleLayer.PaintStyle := Data.PaintStyle;
  RectangleLayer.RotationDegrees := NormalizeAngleDegrees(
    Data.RotationDegrees);
  RectangleLayer.Visible := Data.Visible;
  RectangleLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, RectangleLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertRoundedRectangle(Index: Integer;
  const Data: TMapRakuRoundedRectangleData): Integer;
var
  I: Integer;
  RoundedLayer: TMapRakuRoundedRectangleLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  RoundedLayer := TMapRakuRoundedRectangleLayer.Create(Data.Name,
    Data.Bounds, Data.FillColor, Data.CornerRadii);
  RoundedLayer.Locked := Data.Locked;
  RoundedLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  RoundedLayer.PaintStyle := Data.PaintStyle;
  RoundedLayer.RotationDegrees := NormalizeAngleDegrees(
    Data.RotationDegrees);
  RoundedLayer.Visible := Data.Visible;
  RoundedLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, RoundedLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertEllipse(Index: Integer;
  const Data: TMapRakuEllipseData): Integer;
var
  EllipseLayer: TMapRakuEllipseLayer;
  I: Integer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  EllipseLayer := TMapRakuEllipseLayer.Create(Data.Name, Data.Bounds,
    Data.FillColor);
  EllipseLayer.Locked := Data.Locked;
  EllipseLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  EllipseLayer.PaintStyle := Data.PaintStyle;
  EllipseLayer.RotationDegrees := NormalizeAngleDegrees(
    Data.RotationDegrees);
  EllipseLayer.Visible := Data.Visible;
  EllipseLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, EllipseLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertArc(Index: Integer;
  const Data: TMapRakuArcData): Integer;
var
  ArcLayer: TMapRakuArcLayer;
  I: Integer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  ArcLayer := TMapRakuArcLayer.Create(Data.Name, Data.Bounds);
  ArcLayer.LineCap := Data.LineCap;
  ArcLayer.Locked := Data.Locked;
  ArcLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  ArcLayer.PaintStyle := Data.PaintStyle;
  ArcLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  ArcLayer.StartAngleDegrees := NormalizeMapRakuEllipseAngleDegrees(
    Data.StartAngleDegrees);
  ArcLayer.StrokeColor := Data.StrokeColor;
  ArcLayer.StrokeStyle := Data.StrokeStyle;
  ArcLayer.StrokeWidth := Max(Data.StrokeWidth, 0.1);
  ArcLayer.SweepAngleDegrees := EnsureRange(Data.SweepAngleDegrees,
    0.0, 360.0);
  ArcLayer.Visible := Data.Visible;
  ArcLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, ArcLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertEllipseArcShape(Index: Integer;
  const Data: TMapRakuEllipseArcShapeData): Integer;
var
  I: Integer;
  ShapeLayer: TMapRakuEllipseArcShapeLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  ShapeLayer := TMapRakuEllipseArcShapeLayer.Create(Data.Name,
    Data.Bounds, Data.FillColor);
  ShapeLayer.Locked := Data.Locked;
  ShapeLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  ShapeLayer.PaintStyle := Data.PaintStyle;
  ShapeLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  ShapeLayer.StartAngleDegrees :=
    NormalizeMapRakuEllipseAngleDegrees(Data.StartAngleDegrees);
  ShapeLayer.SweepAngleDegrees := EnsureRange(Data.SweepAngleDegrees,
    0.0, 360.0);
  ShapeLayer.Visible := Data.Visible;
  ShapeLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, ShapeLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertRectangleLine(Index: Integer;
  const Data: TMapRakuRectangleLineData): Integer;
var
  I: Integer;
  LineLayer: TMapRakuRectangleLineLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  LineLayer := TMapRakuRectangleLineLayer.Create(Data.Name, Data.Bounds);
  LineLayer.Locked := Data.Locked;
  LineLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  LineLayer.PaintStyle := Data.PaintStyle;
  LineLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  LineLayer.StrokeColor := Data.StrokeColor;
  LineLayer.StrokeStyle := Data.StrokeStyle;
  LineLayer.StrokeWidth := Max(Data.StrokeWidth, 0.1);
  LineLayer.Visible := Data.Visible;
  LineLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, LineLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertRoundedRectangleLine(Index: Integer;
  const Data: TMapRakuRoundedRectangleLineData): Integer;
var
  I: Integer;
  LineLayer: TMapRakuRoundedRectangleLineLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  LineLayer := TMapRakuRoundedRectangleLineLayer.Create(Data.Name,
    Data.Bounds, Data.CornerRadii);
  LineLayer.Locked := Data.Locked;
  LineLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  LineLayer.PaintStyle := Data.PaintStyle;
  LineLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  LineLayer.StrokeColor := Data.StrokeColor;
  LineLayer.StrokeStyle := Data.StrokeStyle;
  LineLayer.StrokeWidth := Max(Data.StrokeWidth, 0.1);
  LineLayer.Visible := Data.Visible;
  LineLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, LineLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertEllipseLine(Index: Integer;
  const Data: TMapRakuEllipseLineData): Integer;
var
  I: Integer;
  LineLayer: TMapRakuEllipseLineLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  LineLayer := TMapRakuEllipseLineLayer.Create(Data.Name, Data.Bounds);
  LineLayer.Locked := Data.Locked;
  LineLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  LineLayer.PaintStyle := Data.PaintStyle;
  LineLayer.RotationDegrees := NormalizeAngleDegrees(Data.RotationDegrees);
  LineLayer.StrokeColor := Data.StrokeColor;
  LineLayer.StrokeStyle := Data.StrokeStyle;
  LineLayer.StrokeWidth := Max(Data.StrokeWidth, 0.1);
  LineLayer.Visible := Data.Visible;
  LineLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, LineLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertPath(Index: Integer;
  const Data: TVectArtPathData): Integer;
var
  I: Integer;
  PathLayer: TVectArtPathLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  PathLayer := TVectArtPathLayer.Create(Data.Name, Data.Vertices, Data.Closed);
  PathLayer.LineCap := Data.LineCap;
  PathLayer.Locked := Data.Locked;
  PathLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  PathLayer.PaintStyle := Data.PaintStyle;
  PathLayer.StrokeColor := Data.StrokeColor;
  PathLayer.MifStrokeStyle := Data.MifStrokeStyle;
  PathLayer.MapElement := Data.MapElement;
  PathLayer.MapStepCount := Max(Data.MapStepCount,0);
  PathLayer.StrokeWidth := Max(Data.StrokeWidth, 0.0);
  PathLayer.WidthPoints := Data.WidthPoints;
  PathLayer.Visible := Data.Visible;
  PathLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, PathLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertShape(Index: Integer;
  const Data: TMapRakuShapeData): Integer;
var
  I: Integer;
  ShapeLayer: TMapRakuShapeLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  ShapeLayer := TMapRakuShapeLayer.Create(Data.Name, Data.Contours);
  ShapeLayer.FillColor := Data.FillColor;
  ShapeLayer.FillRule := Data.FillRule;
  ShapeLayer.Locked := Data.Locked;
  ShapeLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  ShapeLayer.PaintStyle := Data.PaintStyle;
  ShapeLayer.StrokeColor := Data.StrokeColor;
  ShapeLayer.StrokeStyle := Data.StrokeStyle;
  ShapeLayer.StrokeWidth := Max(Data.StrokeWidth, 0.0);
  ShapeLayer.Visible := Data.Visible;
  ShapeLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, ShapeLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertImage(Index: Integer;
  const Data: TVectArtImageData): Integer;
var
  I: Integer;
  ImageLayer: TVectArtImageLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  ImageLayer := TVectArtImageLayer.Create(Data.Name, Data.PngData,
    Data.Points, Data.SourceKind, Data.SourceFileName);
  ImageLayer.Locked := Data.Locked;
  ImageLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  ImageLayer.Visible := Data.Visible;
  ImageLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, ImageLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

function TVectArtDocument.InsertText(Index: Integer;
  const Data: TMapRakuTextData): Integer;
var
  I: Integer;
  TextLayer: TMapRakuTextLayer;
begin
  Result := EnsureRange(Index, 1, FLayers.Count);
  TextLayer := TMapRakuTextLayer.Create(Data.Name, Data.Bounds,
    Data.Text, Data.FontFamily, Data.FontSize, Data.WrapWidth, Data.TextColor);
  TextLayer.Alignment := Data.Alignment;
  TextLayer.FontStyle := Data.FontStyle;
  TextLayer.LetterSpacingRatio := Data.LetterSpacingRatio;
  TextLayer.IndividualLetterSpacingRatios :=
    Data.IndividualLetterSpacingRatios;
  TextLayer.LineSpacingRatio := Data.LineSpacingRatio;
  TextLayer.Locked := Data.Locked;
  TextLayer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  TextLayer.PaintStyle := Data.PaintStyle;
  TextLayer.RotationDegrees := Data.RotationDegrees;
  TextLayer.TransformMode := Data.TransformMode;
  TextLayer.Visible := Data.Visible;
  TextLayer.Transform := TMapRakuTransform.FromArray(Data.Transform);
  FLayers.Insert(Result, TextLayer);
  for I := 0 to FSelectedLayers.Count - 1 do
    if FSelectedLayers[I] >= Result then
      FSelectedLayers[I] := FSelectedLayers[I] + 1;
  if FSelectedIndex >= Result then
    Inc(FSelectedIndex);
  Changed;
end;

procedure TVectArtDocument.MoveLayer(FromIndex, ToIndex: Integer);
var
  I: Integer;
  Layer: TVectArtLayer;
  Selection: TArray<Integer>;
begin
  if (FromIndex <= 0) or (FromIndex >= FLayers.Count) then
    Exit;
  ToIndex := EnsureRange(ToIndex, 1, FLayers.Count - 1);
  if FromIndex = ToIndex then
    Exit;
  Selection := GetSelectedLayerIndices;
  Layer := FLayers.Extract(FLayers[FromIndex]);
  FLayers.Insert(ToIndex, Layer);
  for I := 0 to High(Selection) do
    if Selection[I] = FromIndex then
      Selection[I] := ToIndex
    else if (FromIndex < ToIndex) and (Selection[I] > FromIndex) and
      (Selection[I] <= ToIndex) then
      Dec(Selection[I])
    else if (FromIndex > ToIndex) and (Selection[I] >= ToIndex) and
      (Selection[I] < FromIndex) then
      Inc(Selection[I]);
  SetSelectedLayersCore(Selection, False);
  Changed;
end;

function TVectArtDocument.RemoveRectangle(Index: Integer;
  out Data: TVectArtRectangleData): Boolean;
var
  I: Integer;
  RectangleLayer: TVectArtRectangleLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index].ClassType = TVectArtRectangleLayer);
  if not Result then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  Data.Bounds := RectangleLayer.Bounds;
  Data.FillColor := RectangleLayer.FillColor;
  Data.Locked := RectangleLayer.Locked;
  Data.Name := RectangleLayer.Name;
  Data.Opacity := RectangleLayer.Opacity;
  Data.RotationDegrees := RectangleLayer.RotationDegrees;
  Data.Visible := RectangleLayer.Visible;
  Data.Transform := RectangleLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveRoundedRectangle(Index: Integer;
  out Data: TMapRakuRoundedRectangleData): Boolean;
var
  I: Integer;
  RoundedLayer: TMapRakuRoundedRectangleLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TMapRakuRoundedRectangleLayer);
  if not Result then
    Exit;
  RoundedLayer := TMapRakuRoundedRectangleLayer(FLayers[Index]);
  Data.Bounds := RoundedLayer.Bounds;
  Data.CornerRadii := RoundedLayer.CornerRadii;
  Data.FillColor := RoundedLayer.FillColor;
  Data.Locked := RoundedLayer.Locked;
  Data.Name := RoundedLayer.Name;
  Data.Opacity := RoundedLayer.Opacity;
  Data.RotationDegrees := RoundedLayer.RotationDegrees;
  Data.Visible := RoundedLayer.Visible;
  Data.Transform := RoundedLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveEllipse(Index: Integer;
  out Data: TMapRakuEllipseData): Boolean;
var
  EllipseLayer: TMapRakuEllipseLayer;
  I: Integer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TMapRakuEllipseLayer);
  if not Result then
    Exit;
  EllipseLayer := TMapRakuEllipseLayer(FLayers[Index]);
  Data.Bounds := EllipseLayer.Bounds;
  Data.FillColor := EllipseLayer.FillColor;
  Data.Locked := EllipseLayer.Locked;
  Data.Name := EllipseLayer.Name;
  Data.Opacity := EllipseLayer.Opacity;
  Data.RotationDegrees := EllipseLayer.RotationDegrees;
  Data.Visible := EllipseLayer.Visible;
  Data.Transform := EllipseLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveArc(Index: Integer;
  out Data: TMapRakuArcData): Boolean;
var
  ArcLayer: TMapRakuArcLayer;
  I: Integer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TMapRakuArcLayer);
  if not Result then
    Exit;
  ArcLayer := TMapRakuArcLayer(FLayers[Index]);
  Data.Bounds := ArcLayer.Bounds;
  Data.LineCap := ArcLayer.LineCap;
  Data.Locked := ArcLayer.Locked;
  Data.Name := ArcLayer.Name;
  Data.Opacity := ArcLayer.Opacity;
  Data.RotationDegrees := ArcLayer.RotationDegrees;
  Data.StartAngleDegrees := ArcLayer.StartAngleDegrees;
  Data.StrokeColor := ArcLayer.StrokeColor;
  Data.StrokeStyle := ArcLayer.StrokeStyle;
  Data.StrokeWidth := ArcLayer.StrokeWidth;
  Data.SweepAngleDegrees := ArcLayer.SweepAngleDegrees;
  Data.Visible := ArcLayer.Visible;
  Data.Transform := ArcLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveRectangleLine(Index: Integer;
  out Data: TMapRakuRectangleLineData): Boolean;
var
  I: Integer;
  LineLayer: TMapRakuRectangleLineLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index].ClassType = TMapRakuRectangleLineLayer);
  if not Result then
    Exit;
  LineLayer := TMapRakuRectangleLineLayer(FLayers[Index]);
  Data.Bounds := LineLayer.Bounds;
  Data.Locked := LineLayer.Locked;
  Data.Name := LineLayer.Name;
  Data.Opacity := LineLayer.Opacity;
  Data.RotationDegrees := LineLayer.RotationDegrees;
  Data.StrokeColor := LineLayer.StrokeColor;
  Data.StrokeStyle := LineLayer.StrokeStyle;
  Data.StrokeWidth := LineLayer.StrokeWidth;
  Data.Visible := LineLayer.Visible;
  Data.Transform := LineLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveRoundedRectangleLine(Index: Integer;
  out Data: TMapRakuRoundedRectangleLineData): Boolean;
var
  I: Integer;
  LineLayer: TMapRakuRoundedRectangleLineLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TMapRakuRoundedRectangleLineLayer);
  if not Result then
    Exit;
  LineLayer := TMapRakuRoundedRectangleLineLayer(FLayers[Index]);
  Data.Bounds := LineLayer.Bounds;
  Data.CornerRadii := LineLayer.CornerRadii;
  Data.Locked := LineLayer.Locked;
  Data.Name := LineLayer.Name;
  Data.Opacity := LineLayer.Opacity;
  Data.RotationDegrees := LineLayer.RotationDegrees;
  Data.StrokeColor := LineLayer.StrokeColor;
  Data.StrokeStyle := LineLayer.StrokeStyle;
  Data.StrokeWidth := LineLayer.StrokeWidth;
  Data.Visible := LineLayer.Visible;
  Data.Transform := LineLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveEllipseArcShape(Index: Integer;
  out Data: TMapRakuEllipseArcShapeData): Boolean;
var
  I: Integer;
  ShapeLayer: TMapRakuEllipseArcShapeLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TMapRakuEllipseArcShapeLayer);
  if not Result then
    Exit;
  ShapeLayer := TMapRakuEllipseArcShapeLayer(FLayers[Index]);
  Data.Bounds := ShapeLayer.Bounds;
  Data.FillColor := ShapeLayer.FillColor;
  Data.Locked := ShapeLayer.Locked;
  Data.Name := ShapeLayer.Name;
  Data.Opacity := ShapeLayer.Opacity;
  Data.RotationDegrees := ShapeLayer.RotationDegrees;
  Data.StartAngleDegrees := ShapeLayer.StartAngleDegrees;
  Data.SweepAngleDegrees := ShapeLayer.SweepAngleDegrees;
  Data.Visible := ShapeLayer.Visible;
  Data.Transform := ShapeLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveEllipseLine(Index: Integer;
  out Data: TMapRakuEllipseLineData): Boolean;
var
  I: Integer;
  LineLayer: TMapRakuEllipseLineLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TMapRakuEllipseLineLayer);
  if not Result then
    Exit;
  LineLayer := TMapRakuEllipseLineLayer(FLayers[Index]);
  Data.Bounds := LineLayer.Bounds;
  Data.Locked := LineLayer.Locked;
  Data.Name := LineLayer.Name;
  Data.Opacity := LineLayer.Opacity;
  Data.RotationDegrees := LineLayer.RotationDegrees;
  Data.StrokeColor := LineLayer.StrokeColor;
  Data.StrokeStyle := LineLayer.StrokeStyle;
  Data.StrokeWidth := LineLayer.StrokeWidth;
  Data.Visible := LineLayer.Visible;
  Data.Transform := LineLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemovePath(Index: Integer;
  out Data: TVectArtPathData): Boolean;
var
  I: Integer;
  PathLayer: TVectArtPathLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TVectArtPathLayer);
  if not Result then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  Data.Closed := PathLayer.Closed;
  Data.LineCap := PathLayer.LineCap;
  Data.Locked := PathLayer.Locked;
  Data.Name := PathLayer.Name;
  Data.Opacity := PathLayer.Opacity;
  Data.Vertices := PathLayer.Vertices;
  Data.StrokeColor := PathLayer.StrokeColor;
  Data.MifStrokeStyle := PathLayer.MifStrokeStyle;
  Data.MapElement := PathLayer.MapElement;
  Data.MapStepCount := PathLayer.MapStepCount;
  Data.StrokeWidth := PathLayer.StrokeWidth;
  Data.WidthPoints := PathLayer.WidthPoints;
  Data.Visible := PathLayer.Visible;
  Data.Transform := PathLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveImage(Index: Integer;
  out Data: TVectArtImageData): Boolean;
var
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Selection: TList<Integer>;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TVectArtImageLayer);
  if not Result then
    Exit;
  ImageLayer := TVectArtImageLayer(FLayers[Index]);
  Data.Locked := ImageLayer.Locked;
  Data.Name := ImageLayer.Name;
  Data.Opacity := ImageLayer.Opacity;
  Data.PngData := Copy(ImageLayer.PngData);
  Data.Points := ImageLayer.Points;
  Data.SourceFileName := ImageLayer.SourceFileName;
  Data.SourceKind := ImageLayer.SourceKind;
  Data.Visible := ImageLayer.Visible;
  Data.Transform := ImageLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveText(Index: Integer;
  out Data: TMapRakuTextData): Boolean;
var
  I: Integer;
  Selection: TList<Integer>;
  TextLayer: TMapRakuTextLayer;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TMapRakuTextLayer);
  if not Result then
    Exit;
  TextLayer := TMapRakuTextLayer(FLayers[Index]);
  Data.Alignment := TextLayer.Alignment;
  Data.Bounds := TextLayer.Bounds;
  Data.FontFamily := TextLayer.FontFamily;
  Data.FontSize := TextLayer.FontSize;
  Data.FontStyle := TextLayer.FontStyle;
  Data.IndividualLetterSpacingRatios :=
    TextLayer.IndividualLetterSpacingRatios;
  Data.LetterSpacingRatio := TextLayer.LetterSpacingRatio;
  Data.LineSpacingRatio := TextLayer.LineSpacingRatio;
  Data.Locked := TextLayer.Locked;
  Data.Name := TextLayer.Name;
  Data.Opacity := TextLayer.Opacity;
  Data.RotationDegrees := TextLayer.RotationDegrees;
  Data.Text := TextLayer.Text;
  Data.TextColor := TextLayer.FillColor;
  Data.TransformMode := TextLayer.TransformMode;
  Data.Visible := TextLayer.Visible;
  Data.Transform := TextLayer.Transform.ToArray;
  Data.WrapWidth := TextLayer.WrapWidth;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.RemoveShape(Index: Integer;
  out Data: TMapRakuShapeData): Boolean;
var
  I: Integer;
  Selection: TList<Integer>;
  ShapeLayer: TMapRakuShapeLayer;
begin
  Result := (Index > 0) and (Index < FLayers.Count) and
    (FLayers[Index] is TMapRakuShapeLayer);
  if not Result then
    Exit;
  ShapeLayer := TMapRakuShapeLayer(FLayers[Index]);
  Data.Contours := ShapeLayer.Contours;
  Data.FillColor := ShapeLayer.FillColor;
  Data.FillRule := ShapeLayer.FillRule;
  Data.Locked := ShapeLayer.Locked;
  Data.Name := ShapeLayer.Name;
  Data.Opacity := ShapeLayer.Opacity;
  Data.StrokeColor := ShapeLayer.StrokeColor;
  Data.StrokeStyle := ShapeLayer.StrokeStyle;
  Data.StrokeWidth := ShapeLayer.StrokeWidth;
  Data.Visible := ShapeLayer.Visible;
  Data.Transform := ShapeLayer.Transform.ToArray;
  FLayers.Delete(Index);
  Selection := TList<Integer>.Create;
  try
    for I := 0 to FSelectedLayers.Count - 1 do
      if FSelectedLayers[I] < Index then
        Selection.Add(FSelectedLayers[I])
      else if FSelectedLayers[I] > Index then
        Selection.Add(FSelectedLayers[I] - 1);
    if (Selection.Count = 0) and (FLayers.Count > 1) then
      Selection.Add(Min(Index, FLayers.Count - 1));
    SetSelectedLayersCore(Selection.ToArray, False);
  finally
    Selection.Free;
  end;
  Changed;
end;

function TVectArtDocument.GetCanvasLayer: TVectArtCanvasLayer;
begin
  if (FLayers.Count > 0) and (FLayers[0] is TVectArtCanvasLayer) then
    Result := TVectArtCanvasLayer(FLayers[0])
  else
    Result := nil;
end;

function TVectArtDocument.GetLayer(Index: Integer): TVectArtLayer;
begin
  Result := FLayers[Index];
end;

function TVectArtDocument.GetLayerCount: Integer;
begin
  Result := FLayers.Count;
end;

function TVectArtDocument.GetSelectionCount: Integer;
begin
  Result := FSelectedLayers.Count;
end;

function TVectArtDocument.IsLayerSelected(Index: Integer): Boolean;
begin
  Result := FSelectedLayers.Contains(Index);
end;

procedure TVectArtDocument.SetCanvasSize(AWidth, AHeight: Integer);
var
  Canvas: TVectArtCanvasLayer;
begin
  Canvas := GetCanvasLayer;
  if Canvas = nil then
    Exit;
  AWidth := Max(AWidth, 1);
  AHeight := Max(AHeight, 1);
  if (Canvas.Width = AWidth) and (Canvas.Height = AHeight) then
    Exit;
  Canvas.Width := AWidth;
  Canvas.Height := AHeight;
  Changed;
end;

procedure TVectArtDocument.SetSelectedIndex(const Value: Integer);
var
  NewValue: Integer;
begin
  NewValue := EnsureRange(Value, -1, FLayers.Count - 1);
  if (FSelectedIndex = NewValue) and
    (((NewValue < 0) and (FSelectedLayers.Count = 0)) or
     ((FSelectedLayers.Count = 1) and (FSelectedLayers[0] = NewValue))) then
    Exit;
  FSelectedLayers.Clear;
  if NewValue >= 0 then
    FSelectedLayers.Add(NewValue);
  FSelectedIndex := NewValue;
  SelectionChanged;
end;

procedure TVectArtDocument.SetSelectedLayers(const Indices: array of Integer);
begin
  SetSelectedLayersCore(Indices, True);
end;

procedure TVectArtDocument.SelectLayerRange(AnchorIndex,
  TargetIndex: Integer; Additive: Boolean);
var
  FirstIndex: Integer;
  I: Integer;
  LastIndex: Integer;
  Selection: TList<Integer>;
begin
  if FLayers.Count <= 1 then
    Exit;
  AnchorIndex := EnsureRange(AnchorIndex, 1, FLayers.Count - 1);
  TargetIndex := EnsureRange(TargetIndex, 1, FLayers.Count - 1);
  FirstIndex := Min(AnchorIndex, TargetIndex);
  LastIndex := Max(AnchorIndex, TargetIndex);
  Selection := TList<Integer>.Create;
  try
    if Additive then
      Selection.AddRange(FSelectedLayers);
    for I := FirstIndex to LastIndex do
      if not Selection.Contains(I) then
        Selection.Add(I);
    Selection.Sort;
    // レイヤー操作用の昇順選択を保ちつつ、最後に指した範囲端をアクティブにする。
    SetSelectedLayersCore(Selection.ToArray, False);
    FSelectedIndex := TargetIndex;
    SelectionChanged;
  finally
    Selection.Free;
  end;
end;

procedure TVectArtDocument.SetSelectedLayersCore(
  const Indices: array of Integer; Notify: Boolean);
var
  I: Integer;
  Index: Integer;
  HasSelectionChanged: Boolean;
  ValidIndices: TList<Integer>;
begin
  ValidIndices := TList<Integer>.Create;
  try
    for Index in Indices do
      if (Index > 0) and (Index < FLayers.Count) and
        not ValidIndices.Contains(Index) then
        ValidIndices.Add(Index);
    HasSelectionChanged := ValidIndices.Count <> FSelectedLayers.Count;
    if not HasSelectionChanged then
      for I := 0 to ValidIndices.Count - 1 do
        if ValidIndices[I] <> FSelectedLayers[I] then
        begin
          HasSelectionChanged := True;
          Break;
        end;
    if not HasSelectionChanged then
      Exit;
    FSelectedLayers.Clear;
    FSelectedLayers.AddRange(ValidIndices);
    if FSelectedLayers.Count > 0 then
      FSelectedIndex := FSelectedLayers[FSelectedLayers.Count - 1]
    else
      FSelectedIndex := -1;
  finally
    ValidIndices.Free;
  end;
  if Notify then
    SelectionChanged;
end;

procedure TVectArtDocument.ToggleSelectedLayer(Index: Integer);
var
  Added: Boolean;
  Selection: TList<Integer>;
begin
  if (Index <= 0) or (Index >= FLayers.Count) then
    Exit;
  Selection := TList<Integer>.Create;
  try
    Selection.AddRange(FSelectedLayers);
    Added := not Selection.Contains(Index);
    if not Added then
      Selection.Remove(Index)
    else
      Selection.Add(Index);
    Selection.Sort;
    // 選択配列は積層順のまま保ち、Ctrlクリックした対象だけをアクティブとして別管理する。
    SetSelectedLayersCore(Selection.ToArray, False);
    if Added then
      FSelectedIndex := Index
    else if Selection.Count > 0 then
      FSelectedIndex := Selection[Selection.Count - 1]
    else
      FSelectedIndex := -1;
    SelectionChanged;
  finally
    Selection.Free;
  end;
end;

procedure TVectArtDocument.SetRectangleBounds(Index: Integer;
  const Value: TRectF);
var
  CurrentBounds: TRectF;
  RectangleLayer: TVectArtRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtRectangleLayer) then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  CurrentBounds := RectangleLayer.Bounds;
  if SameValue(CurrentBounds.Left, Value.Left) and
    SameValue(CurrentBounds.Top, Value.Top) and
    SameValue(CurrentBounds.Right, Value.Right) and
    SameValue(CurrentBounds.Bottom, Value.Bottom) then
    Exit;
  RectangleLayer.Bounds := Value;
  if RectangleLayer is TMapRakuRoundedRectangleLayer then
    TMapRakuRoundedRectangleLayer(RectangleLayer).CornerRadii :=
      ClampMapRakuCornerRadii(Value,
        TMapRakuRoundedRectangleLayer(RectangleLayer).CornerRadii);
  Changed;
end;

procedure TVectArtDocument.SetRoundedRectangleCornerRadii(Index: Integer;
  const Value: TMapRakuCornerRadii);
var
  NewValue: TMapRakuCornerRadii;
  RoundedLayer: TMapRakuRoundedRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuRoundedRectangleLayer) then
    Exit;
  RoundedLayer := TMapRakuRoundedRectangleLayer(FLayers[Index]);
  NewValue := ClampMapRakuCornerRadii(RoundedLayer.Bounds, Value);
  if SameValue(RoundedLayer.CornerRadii.TopLeft, NewValue.TopLeft) and
    SameValue(RoundedLayer.CornerRadii.TopRight, NewValue.TopRight) and
    SameValue(RoundedLayer.CornerRadii.BottomRight, NewValue.BottomRight) and
    SameValue(RoundedLayer.CornerRadii.BottomLeft, NewValue.BottomLeft) then
    Exit;
  RoundedLayer.CornerRadii := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetRectangleFillColor(Index: Integer;
  Value: TColor);
var
  RectangleLayer: TVectArtRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtRectangleLayer) then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  if RectangleLayer.FillColor = Value then
    Exit;
  RectangleLayer.FillColor := Value;
  Changed;
end;

procedure TVectArtDocument.SetRectangleRotation(Index: Integer;
  Value: Single);
var
  NewValue: Single;
  RectangleLayer: TVectArtRectangleLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtRectangleLayer) then
    Exit;
  RectangleLayer := TVectArtRectangleLayer(FLayers[Index]);
  NewValue := NormalizeAngleDegrees(Value);
  if SameValue(RectangleLayer.RotationDegrees, NewValue) then
    Exit;
  RectangleLayer.RotationDegrees := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetRectangleLineBounds(Index: Integer;
  const Value: TRectF);
var
  CurrentBounds: TRectF;
  LineLayer: TMapRakuRectangleLineLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuRectangleLineLayer) then
    Exit;
  LineLayer := TMapRakuRectangleLineLayer(FLayers[Index]);
  CurrentBounds := LineLayer.Bounds;
  if SameValue(CurrentBounds.Left, Value.Left) and
    SameValue(CurrentBounds.Top, Value.Top) and
    SameValue(CurrentBounds.Right, Value.Right) and
    SameValue(CurrentBounds.Bottom, Value.Bottom) then
    Exit;
  LineLayer.Bounds := Value;
  if LineLayer is TMapRakuRoundedRectangleLineLayer then
    TMapRakuRoundedRectangleLineLayer(LineLayer).CornerRadii :=
      ClampMapRakuCornerRadii(Value,
        TMapRakuRoundedRectangleLineLayer(LineLayer).CornerRadii);
  Changed;
end;

procedure TVectArtDocument.SetRoundedRectangleLineCornerRadii(Index: Integer;
  const Value: TMapRakuCornerRadii);
var
  LineLayer: TMapRakuRoundedRectangleLineLayer;
  NewValue: TMapRakuCornerRadii;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuRoundedRectangleLineLayer) then
    Exit;
  LineLayer := TMapRakuRoundedRectangleLineLayer(FLayers[Index]);
  NewValue := ClampMapRakuCornerRadii(LineLayer.Bounds, Value);
  if SameValue(LineLayer.CornerRadii.TopLeft, NewValue.TopLeft) and
    SameValue(LineLayer.CornerRadii.TopRight, NewValue.TopRight) and
    SameValue(LineLayer.CornerRadii.BottomRight, NewValue.BottomRight) and
    SameValue(LineLayer.CornerRadii.BottomLeft, NewValue.BottomLeft) then
    Exit;
  LineLayer.CornerRadii := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetRectangleLineRotation(Index: Integer;
  Value: Single);
var
  LineLayer: TMapRakuRectangleLineLayer;
  NewValue: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuRectangleLineLayer) then
    Exit;
  LineLayer := TMapRakuRectangleLineLayer(FLayers[Index]);
  NewValue := NormalizeAngleDegrees(Value);
  if SameValue(LineLayer.RotationDegrees, NewValue) then
    Exit;
  LineLayer.RotationDegrees := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetRectangleLineStroke(Index: Integer;
  Color: TColor; Width: Single; Style: TVectArtMifStrokeStyle);
var
  LineLayer: TMapRakuRectangleLineLayer;
  NewWidth: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuRectangleLineLayer) then
    Exit;
  LineLayer := TMapRakuRectangleLineLayer(FLayers[Index]);
  NewWidth := Max(Width, 0.1);
  if (LineLayer.StrokeColor = Color) and
    SameValue(LineLayer.StrokeWidth, NewWidth) and
    (LineLayer.StrokeStyle = Style) then
    Exit;
  LineLayer.StrokeColor := Color;
  LineLayer.StrokeWidth := NewWidth;
  LineLayer.StrokeStyle := Style;
  Changed;
end;

procedure TVectArtDocument.SetArcBounds(Index: Integer;
  const Value: TRectF);
var
  ArcLayer: TMapRakuArcLayer;
  CurrentBounds: TRectF;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuArcLayer) then
    Exit;
  ArcLayer := TMapRakuArcLayer(FLayers[Index]);
  CurrentBounds := ArcLayer.Bounds;
  if SameValue(CurrentBounds.Left, Value.Left) and
    SameValue(CurrentBounds.Top, Value.Top) and
    SameValue(CurrentBounds.Right, Value.Right) and
    SameValue(CurrentBounds.Bottom, Value.Bottom) then
    Exit;
  ArcLayer.Bounds := Value;
  Changed;
end;

procedure TVectArtDocument.SetArcAngles(Index: Integer; StartAngleDegrees,
  SweepAngleDegrees: Single);
var
  ArcLayer: TMapRakuArcLayer;
  NewStartAngle: Single;
  NewSweepAngle: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuArcLayer) then
    Exit;
  ArcLayer := TMapRakuArcLayer(FLayers[Index]);
  NewStartAngle := NormalizeMapRakuEllipseAngleDegrees(
    StartAngleDegrees);
  NewSweepAngle := EnsureRange(SweepAngleDegrees, 0.0, 360.0);
  if SameValue(ArcLayer.StartAngleDegrees, NewStartAngle) and
    SameValue(ArcLayer.SweepAngleDegrees, NewSweepAngle) then
    Exit;
  ArcLayer.StartAngleDegrees := NewStartAngle;
  ArcLayer.SweepAngleDegrees := NewSweepAngle;
  Changed;
end;

procedure TVectArtDocument.SetArcLineCap(Index: Integer;
  Value: TVectArtLineCap);
var
  ArcLayer: TMapRakuArcLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuArcLayer) then
    Exit;
  ArcLayer := TMapRakuArcLayer(FLayers[Index]);
  if ArcLayer.LineCap = Value then
    Exit;
  ArcLayer.LineCap := Value;
  Changed;
end;

procedure TVectArtDocument.SetArcRotation(Index: Integer; Value: Single);
var
  ArcLayer: TMapRakuArcLayer;
  NewValue: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuArcLayer) then
    Exit;
  ArcLayer := TMapRakuArcLayer(FLayers[Index]);
  NewValue := NormalizeAngleDegrees(Value);
  if SameValue(ArcLayer.RotationDegrees, NewValue) then
    Exit;
  ArcLayer.RotationDegrees := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetEllipseArcShapeAngles(Index: Integer;
  StartAngleDegrees, SweepAngleDegrees: Single);
var
  NewStartAngle: Single;
  NewSweepAngle: Single;
  ShapeLayer: TMapRakuEllipseArcShapeLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuEllipseArcShapeLayer) then
    Exit;
  ShapeLayer := TMapRakuEllipseArcShapeLayer(FLayers[Index]);
  NewStartAngle := NormalizeMapRakuEllipseAngleDegrees(
    StartAngleDegrees);
  NewSweepAngle := EnsureRange(SweepAngleDegrees, 0.0, 360.0);
  if SameValue(ShapeLayer.StartAngleDegrees, NewStartAngle) and
    SameValue(ShapeLayer.SweepAngleDegrees, NewSweepAngle) then
    Exit;
  ShapeLayer.StartAngleDegrees := NewStartAngle;
  ShapeLayer.SweepAngleDegrees := NewSweepAngle;
  Changed;
end;

procedure TVectArtDocument.SetArcStroke(Index: Integer; Color: TColor;
  Width: Single; Style: TVectArtMifStrokeStyle);
var
  ArcLayer: TMapRakuArcLayer;
  NewWidth: Single;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuArcLayer) then
    Exit;
  ArcLayer := TMapRakuArcLayer(FLayers[Index]);
  NewWidth := Max(Width, 0.1);
  if (ArcLayer.StrokeColor = Color) and
    SameValue(ArcLayer.StrokeWidth, NewWidth) and
    (ArcLayer.StrokeStyle = Style) then
    Exit;
  ArcLayer.StrokeColor := Color;
  ArcLayer.StrokeWidth := NewWidth;
  ArcLayer.StrokeStyle := Style;
  Changed;
end;

procedure TVectArtDocument.SetImagePoints(Index: Integer;
  const Points: TVectArtImagePoints);
var
  ImageLayer: TVectArtImageLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtImageLayer) then
    Exit;
  ImageLayer := TVectArtImageLayer(FLayers[Index]);
  ImageLayer.Points := Points;
  Changed;
end;

procedure TVectArtDocument.SetTextData(Index: Integer;
  const Data: TMapRakuTextData);
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuTextLayer) then
    Exit;
  SetTextLayerData(TMapRakuTextLayer(FLayers[Index]), Data);
end;

procedure TVectArtDocument.SetTextLayerData(Layer: TMapRakuTextLayer;
  const Data: TMapRakuTextData);
begin
  if Layer = nil then
    Exit;
  Layer.Alignment := Data.Alignment;
  Layer.Bounds := Data.Bounds;
  Layer.FillColor := Data.TextColor;
  Layer.FontFamily := Data.FontFamily;
  Layer.FontSize := Max(Data.FontSize, 1.0);
  Layer.FontStyle := Data.FontStyle;
  Layer.Text := Data.Text;
  if Layer is TMapRakuTextPathLayer then
  begin
    TMapRakuTextPathLayer(Layer).Attachment :=
      Data.TextPathAttachment;
    TMapRakuTextPathLayer(Layer).CharacterPathOffsets :=
      Data.CharacterPathOffsets;
    TMapRakuTextPathLayer(Layer).CharacterPositionManual :=
      Data.CharacterPositionManual;
    TMapRakuTextPathLayer(Layer).CharacterScales :=
      Data.CharacterScales;
  end;
  if Layer is TMapRakuTextPathLayer then
    Layer.LetterSpacingRatio := 0
  else
    Layer.LetterSpacingRatio := EnsureRange(Data.LetterSpacingRatio,
      SCREEN_LAYOUT_TEXT_LETTER_SPACING_MIN,
      SCREEN_LAYOUT_TEXT_LETTER_SPACING_MAX);
  Layer.LineSpacingRatio := EnsureRange(Data.LineSpacingRatio,
    SCREEN_LAYOUT_TEXT_LINE_SPACING_MIN,
    SCREEN_LAYOUT_TEXT_LINE_SPACING_MAX);
  Layer.Locked := Data.Locked;
  Layer.Name := Data.Name;
  Layer.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  Layer.RotationDegrees := Data.RotationDegrees;
  if Layer is TMapRakuTextPathLayer then
    Layer.IndividualLetterSpacingRatios := nil
  else
    Layer.IndividualLetterSpacingRatios :=
      Data.IndividualLetterSpacingRatios;
  Layer.TransformMode := Data.TransformMode;
  Layer.Visible := Data.Visible;
  if Layer is TMapRakuTextPathLayer then
    Layer.WrapWidth := 0
  else
    Layer.WrapWidth := Max(Data.WrapWidth, 0.0);
  Changed;
end;

procedure TVectArtDocument.SetPathVertices(Index: Integer;
  const Vertices: TArray<TMapRakuVertex>);
var
  I: Integer;
  Layer: TVectArtLayer;
  OldVertices: TArray<TMapRakuVertex>;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not FLayers[Index].SupportsPathEditing then
    Exit;
  Layer := FLayers[Index];
  OldVertices := Layer.EditablePathVertices;
  if Length(OldVertices) = Length(Vertices) then
  begin
    if Length(Vertices) = 0 then
      Exit;
    for I := 0 to High(Vertices) do
      if not SameValue(OldVertices[I].Position.X, Vertices[I].Position.X) or
        not SameValue(OldVertices[I].Position.Y, Vertices[I].Position.Y) or
        not SameValue(OldVertices[I].IncomingControl.X,
          Vertices[I].IncomingControl.X) or
        not SameValue(OldVertices[I].IncomingControl.Y,
          Vertices[I].IncomingControl.Y) or
        not SameValue(OldVertices[I].OutgoingControl.X,
          Vertices[I].OutgoingControl.X) or
        not SameValue(OldVertices[I].OutgoingControl.Y,
          Vertices[I].OutgoingControl.Y) or
        (OldVertices[I].OutgoingSegment <> Vertices[I].OutgoingSegment) or
        (OldVertices[I].Kind <> Vertices[I].Kind) then
        Break;
    if I > High(Vertices) then
      Exit;
  end;
  Layer.AssignEditablePathVertices(Vertices);
  Changed;
end;

procedure TVectArtDocument.SetPathLineCap(Index: Integer;
  Value: TVectArtLineCap);
var
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if PathLayer.Closed then
    Exit;
  if PathLayer.LineCap = Value then
    Exit;
  PathLayer.LineCap := Value;
  Changed;
end;

procedure TVectArtDocument.SetPathWidthPoints(Index: Integer;
  const WidthPoints: TArray<TMapRakuStrokeWidthPoint>);
var
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if PathLayer.Closed then
    Exit;
  PathLayer.WidthPoints := WidthPoints;
  Changed;
end;

procedure TVectArtDocument.SetPathStroke(Index: Integer; Color: TColor;
  Width: Single; Style: TVectArtMifStrokeStyle);
var
  NewWidth: Single;
  PathLayer: TVectArtPathLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TVectArtPathLayer) then
    Exit;
  PathLayer := TVectArtPathLayer(FLayers[Index]);
  if PathLayer.Closed then
    Exit;
  NewWidth := Max(Width, 0.0);
  if (PathLayer.StrokeColor = Color) and
    SameValue(PathLayer.StrokeWidth, NewWidth) and
    (PathLayer.MifStrokeStyle = Style) then
    Exit;
  PathLayer.StrokeColor := Color;
  PathLayer.StrokeWidth := NewWidth;
  PathLayer.MifStrokeStyle := Style;
  Changed;
end;

procedure TVectArtDocument.SetShapeContours(Index: Integer;
  const Contours: TArray<TMapRakuContour>);
var
  ShapeLayer: TMapRakuShapeLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuShapeLayer) then
    Exit;
  ShapeLayer := TMapRakuShapeLayer(FLayers[Index]);
  if ShapeContoursEqual(ShapeLayer.FContours, Contours) then
    Exit;
  ShapeLayer.Contours := Contours;
  Changed;
end;

procedure TVectArtDocument.SetShapeFill(Index: Integer; Color: TColor;
  FillRule: TMapRakuFillRule);
var
  ShapeLayer: TMapRakuShapeLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuShapeLayer) then
    Exit;
  ShapeLayer := TMapRakuShapeLayer(FLayers[Index]);
  if (ShapeLayer.FillColor = Color) and
    (ShapeLayer.FillRule = FillRule) then
    Exit;
  ShapeLayer.FillColor := Color;
  ShapeLayer.FillRule := FillRule;
  Changed;
end;

procedure TVectArtDocument.SetShapeStroke(Index: Integer; Color: TColor;
  Width: Single; Style: TVectArtMifStrokeStyle);
var
  NewWidth: Single;
  ShapeLayer: TMapRakuShapeLayer;
begin
  if (Index <= 0) or (Index >= FLayers.Count) or
    not (FLayers[Index] is TMapRakuShapeLayer) then
    Exit;
  ShapeLayer := TMapRakuShapeLayer(FLayers[Index]);
  NewWidth := Max(Width, 0.0);
  if (ShapeLayer.StrokeColor = Color) and
    SameValue(ShapeLayer.StrokeWidth, NewWidth) and
    (ShapeLayer.StrokeStyle = Style) then
    Exit;
  ShapeLayer.StrokeColor := Color;
  ShapeLayer.StrokeWidth := NewWidth;
  ShapeLayer.StrokeStyle := Style;
  Changed;
end;

procedure TVectArtDocument.SetLayerLocked(Index: Integer; Value: Boolean);
begin
  if (Index < 0) or (Index >= FLayers.Count) or
    (FLayers[Index].Locked = Value) then
    Exit;
  FLayers[Index].Locked := Value;
  Changed;
end;

procedure TVectArtDocument.SetLayerOpacity(Index: Integer; Value: Single);
var
  NewValue: Single;
begin
  if (Index < 0) or (Index >= FLayers.Count) then
    Exit;
  NewValue := EnsureRange(Value, 0.0, 1.0);
  if SameValue(FLayers[Index].Opacity, NewValue) then
    Exit;
  FLayers[Index].Opacity := NewValue;
  Changed;
end;

procedure TVectArtDocument.SetLayerVisible(Index: Integer; Value: Boolean);
begin
  if (Index < 0) or (Index >= FLayers.Count) or
    (FLayers[Index].Visible = Value) then
    Exit;
  FLayers[Index].Visible := Value;
  Changed;
end;

end.

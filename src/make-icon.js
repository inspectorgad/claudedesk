#!/usr/bin/env osascript -l JavaScript
// make-icon.js — draw a colored badge onto a source .icns and emit an .iconset.
//
// Usage:
//   osascript -l JavaScript make-icon.js <source.icns> <badge text> <hex color> <out.iconset>
//
// Runs with the AppKit that ships with macOS; no third-party tools.

ObjC.import('AppKit');
ObjC.import('Foundation');

function hexToColor(hex) {
  hex = String(hex).replace(/^#/, '');
  if (hex.length !== 6) throw new Error('badge color must be 6 hex digits, got ' + hex);
  var r = parseInt(hex.substr(0, 2), 16) / 255;
  var g = parseInt(hex.substr(2, 2), 16) / 255;
  var b = parseInt(hex.substr(4, 2), 16) / 255;
  return $.NSColor.colorWithSRGBRedGreenBlueAlpha(r, g, b, 1.0);
}

// iconutil expects exactly these file names.
var SLOTS = [
  [16,   'icon_16x16.png'],
  [32,   'icon_16x16@2x.png'],
  [32,   'icon_32x32.png'],
  [64,   'icon_32x32@2x.png'],
  [128,  'icon_128x128.png'],
  [256,  'icon_128x128@2x.png'],
  [256,  'icon_256x256.png'],
  [512,  'icon_256x256@2x.png'],
  [512,  'icon_512x512.png'],
  [1024, 'icon_512x512@2x.png']
];

function renderSlot(src, px, badgeText, color) {
  var rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, px, px, 8, 4, true, false, $.NSCalibratedRGBColorSpace, 0, 0);
  rep.setSize($.NSMakeSize(px, px));

  $.NSGraphicsContext.saveGraphicsState;
  var ctx = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep);
  $.NSGraphicsContext.setCurrentContext(ctx);
  ctx.setImageInterpolation($.NSImageInterpolationHigh);

  // Base icon.
  src.drawInRectFromRectOperationFraction(
    $.NSMakeRect(0, 0, px, px), $.NSMakeRect(0, 0, 0, 0), $.NSCompositingOperationSourceOver, 1.0);

  // Ribbon across the lower part of the icon.
  var margin = Math.round(px * 0.08);
  var h = Math.round(px * 0.30);
  var y = Math.round(px * 0.05);
  var w = px - 2 * margin;
  var radius = Math.max(1, Math.round(h * 0.28));
  var rect = $.NSMakeRect(margin, y, w, h);
  var path = $.NSBezierPath.bezierPathWithRoundedRectXRadiusYRadius(rect, radius, radius);
  color.set;
  path.fill;

  // Label (skipped at tiny sizes where it would be an unreadable smudge).
  if (px >= 64 && badgeText.length > 0) {
    var fontSize = h * 0.62;
    var font = $.NSFont.boldSystemFontOfSize(fontSize);
    var attrs = $.NSMutableDictionary.alloc.init;
    attrs.setObjectForKey(font, $.NSFontAttributeName);
    attrs.setObjectForKey($.NSColor.whiteColor, $.NSForegroundColorAttributeName);
    var str = $.NSAttributedString.alloc.initWithStringAttributes($(badgeText), attrs);
    var sz = str.size;
    // Shrink to fit if the label is wide.
    if (sz.width > w * 0.9) {
      fontSize = fontSize * (w * 0.9) / sz.width;
      font = $.NSFont.boldSystemFontOfSize(fontSize);
      attrs.setObjectForKey(font, $.NSFontAttributeName);
      str = $.NSAttributedString.alloc.initWithStringAttributes($(badgeText), attrs);
      sz = str.size;
    }
    str.drawAtPoint($.NSMakePoint(margin + (w - sz.width) / 2, y + (h - sz.height) / 2));
  }

  ctx.flushGraphics;
  $.NSGraphicsContext.restoreGraphicsState;
  return rep;
}

function run(argv) {
  if (argv.length < 4) {
    throw new Error('usage: make-icon.js <source.icns> <badge text> <hex color> <out.iconset>');
  }
  var srcPath = argv[0], badgeText = argv[1], colorHex = argv[2], outDir = argv[3];

  var src = $.NSImage.alloc.initWithContentsOfFile($(srcPath));
  if (src.isNil()) throw new Error('cannot load source icon: ' + srcPath);
  var color = hexToColor(colorHex);

  var fm = $.NSFileManager.defaultManager;
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError($(outDir), true, $(), null);

  for (var i = 0; i < SLOTS.length; i++) {
    var px = SLOTS[i][0], name = SLOTS[i][1];
    var rep = renderSlot(src, px, badgeText, color);
    var png = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $({}));
    var ok = png.writeToFileAtomically($(outDir + '/' + name), true);
    if (!ok) throw new Error('failed to write ' + name);
  }
  return 'wrote ' + SLOTS.length + ' images to ' + outDir;
}

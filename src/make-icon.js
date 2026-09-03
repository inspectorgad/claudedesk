#!/usr/bin/env osascript -l JavaScript
// make-icon.js — draw a colored badge onto a source .icns and emit an .iconset.
//
// Usage:
//   osascript -l JavaScript make-icon.js <source.icns> <badge text> <hex color> <out.iconset>
//
// Runs with the AppKit that ships with macOS; no third-party tools.

ObjC.import('AppKit');
ObjC.import('Foundation');
ObjC.import('CoreText');
ObjC.import('CoreGraphics');

// JXA does not expose every AppKit convenience on every class (for example
// NSAttributedString's initWithString:attributes: is missing on the alloc
// placeholder), so text is measured and drawn through a chain of approaches.
// The first one that works is used; errors are collected for diagnostics.
var TEXT_ERRORS = [];
var TEXT_METHOD = 'none';

function makeAttributedString(text, font, color) {
  var str = $.NSMutableAttributedString.alloc.initWithString($(text));
  var range = $.NSMakeRange(0, str.length);
  str.addAttributeValueRange($.NSFontAttributeName, font, range);
  str.addAttributeValueRange($.NSForegroundColorAttributeName, color, range);
  return str;
}

function makeAttrsDict(font, color) {
  var attrs = $.NSMutableDictionary.alloc.init;
  attrs.setObjectForKey(font, $.NSFontAttributeName);
  attrs.setObjectForKey(color, $.NSForegroundColorAttributeName);
  return attrs;
}

// Returns {width, height} or throws.
function measureText(text, font, color) {
  var errs = [];
  try {
    var s = makeAttributedString(text, font, color);
    var sz = s.size;
    if (sz && typeof sz.width === 'number') return { width: sz.width, height: sz.height };
    errs.push('NSAttributedString.size unavailable');
  } catch (e) { errs.push('attributed.size: ' + e); }
  try {
    var sz2 = $(text).sizeWithAttributes(makeAttrsDict(font, color));
    if (sz2 && typeof sz2.width === 'number') return { width: sz2.width, height: sz2.height };
    errs.push('NSString.sizeWithAttributes unavailable');
  } catch (e) { errs.push('sizeWithAttributes: ' + e); }
  try {
    var line = $.CTLineCreateWithAttributedString(makeAttributedString(text, font, color));
    var ascent = Ref(), descent = Ref(), leading = Ref();
    var w = $.CTLineGetTypographicBounds(line, ascent, descent, leading);
    return { width: w, height: ascent[0] + descent[0], ctAscent: ascent[0], ctDescent: descent[0] };
  } catch (e) { errs.push('CoreText measure: ' + e); }
  TEXT_ERRORS = TEXT_ERRORS.concat(errs);
  throw new Error('cannot measure text: ' + errs.join(' | '));
}

// Draws text with its bottom-left at (x, y) in the current context, or throws.
function drawText(text, font, color, x, y, ctx, metrics) {
  var errs = [];
  try {
    var s = makeAttributedString(text, font, color);
    if (typeof s.drawAtPoint === 'function') { s.drawAtPoint($.NSMakePoint(x, y)); return 'attributed.drawAtPoint'; }
    errs.push('NSAttributedString.drawAtPoint unavailable');
  } catch (e) { errs.push('attributed.drawAtPoint: ' + e); }
  try {
    var ns = $(text);
    if (typeof ns.drawAtPointWithAttributes === 'function') {
      ns.drawAtPointWithAttributes($.NSMakePoint(x, y), makeAttrsDict(font, color));
      return 'NSString.drawAtPointWithAttributes';
    }
    errs.push('NSString.drawAtPointWithAttributes unavailable');
  } catch (e) { errs.push('drawAtPointWithAttributes: ' + e); }
  try {
    var line = $.CTLineCreateWithAttributedString(makeAttributedString(text, font, color));
    var cg = ctx.CGContext;
    var baseline = y + (metrics && typeof metrics.ctDescent === 'number' ? metrics.ctDescent : font.descender * -1);
    $.CGContextSaveGState(cg);
    $.CGContextSetTextMatrix(cg, $.CGAffineTransformMake(1, 0, 0, 1, 0, 0));
    $.CGContextSetTextPosition(cg, x, baseline);
    $.CTLineDraw(line, cg);
    $.CGContextRestoreGState(cg);
    return 'CoreText';
  } catch (e) { errs.push('CoreText draw: ' + e); }
  TEXT_ERRORS = TEXT_ERRORS.concat(errs);
  throw new Error('cannot draw text: ' + errs.join(' | '));
}

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
    var white = $.NSColor.whiteColor;
    var m = measureText(badgeText, font, white);
    // Shrink to fit if the label is wide.
    if (m.width > w * 0.9) {
      fontSize = fontSize * (w * 0.9) / m.width;
      font = $.NSFont.boldSystemFontOfSize(fontSize);
      m = measureText(badgeText, font, white);
    }
    var tx = margin + (w - m.width) / 2;
    var ty = y + (h - m.height) / 2;
    TEXT_METHOD = drawText(badgeText, font, white, tx, ty, ctx, m);
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
  var note = TEXT_ERRORS.length ? ' (fallbacks tried: ' + TEXT_ERRORS.join(' | ') + ')' : '';
  return 'wrote ' + SLOTS.length + ' images to ' + outDir + ' using ' + TEXT_METHOD + note;
}

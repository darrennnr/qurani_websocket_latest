// // ==================== MUSHAF LAYOUT ENGINE - SIMPLIFIED VERSION ====================

// import 'dart:ui' as ui;
// import 'dart:math' as math;
// import 'package:flutter/material.dart';
// import '../main/stt.dart'; // Import AyatData from main file

// // 1. KONSTANTA RENDERING DETERMINISTIK
// class MushafRenderingConstants {
//   static const double PAGE_WIDTH = 350.0;
//   static const double PAGE_HEIGHT = 500.0;
//   static const double LINE_HEIGHT = 32.0;
//   static const int LINES_PER_PAGE = 15;
//   static const double BASE_FONT_SIZE = 24.0;
//   static const double KASHIDA_AVG_WIDTH = 8.0;
//   static const int MAX_KASHIDA_PER_SLOT = 3;
//   static const double MARGIN_LEFT = 16.0;
//   static const double MARGIN_RIGHT = 16.0;
//   static const double TARGET_LINE_WIDTH = PAGE_WIDTH - MARGIN_LEFT - MARGIN_RIGHT;
  
//   static const double FONT_SIZE_STEP = 1.0;
//   static const double MIN_FONT_SIZE = 18.0;
// }

// // 2. SIMPLIFIED DATA STRUCTURES
// class LineBreak {
//   final int startWordIndex;
//   final int endWordIndex;
//   final List<KashidaInsertion> kashidaInsertions;
//   final double actualWidth;
  
//   LineBreak({
//     required this.startWordIndex,
//     required this.endWordIndex,
//     required this.kashidaInsertions,
//     required this.actualWidth,
//   });
// }

// class KashidaInsertion {
//   final int wordIndex;
//   final int slotIndex;
//   final int count;
  
//   KashidaInsertion({
//     required this.wordIndex,
//     required this.slotIndex,
//     required this.count,
//   });
// }

// // 3. SIMPLIFIED MUSHAF LAYOUT ENGINE
// class MushafLayoutEngine {
//   final double targetWidth = MushafRenderingConstants.TARGET_LINE_WIDTH;
//   final int targetLines = MushafRenderingConstants.LINES_PER_PAGE;

//   // MAIN PIPELINE FUNCTION - SIMPLIFIED
//   Future<List<LineBreak>> layoutPage(List<AyatData> ayatList) async {
//     print('🔥 MUSHAF_LAYOUT: Starting layout for ${ayatList.length} ayats');
    
//     try {
//       // Extract all words
//       final allWords = <String>[];
//       for (final ayat in ayatList) {
//         allWords.addAll(ayat.wordsArrayNt); // Use words without tashkeel
//       }
      
//       print('🔥 MUSHAF_LAYOUT: Total words to layout: ${allWords.length}');
      
//       if (allWords.isEmpty) {
//         print('🔥 MUSHAF_LAYOUT: No words found, returning empty layout');
//         return _createEmptyLayout();
//       }

//       // Simple line breaking algorithm
//       final lineBreaks = await _performSimpleLineBreaking(allWords);
      
//       print('🔥 MUSHAF_LAYOUT: Generated ${lineBreaks.length} lines');
//       return lineBreaks;
      
//     } catch (e, stackTrace) {
//       print('🔥 MUSHAF_LAYOUT: ERROR: $e');
//       print('🔥 MUSHAF_LAYOUT: STACKTRACE: $stackTrace');
      
//       // Return fallback layout
//       return _createEmptyLayout();
//     }
//   }

//   // SIMPLE LINE BREAKING ALGORITHM
//   Future<List<LineBreak>> _performSimpleLineBreaking(List<String> words) async {
//     print('🔥 MUSHAF_LAYOUT: Starting simple line breaking');
    
//     final List<LineBreak> lines = [];
//     final double maxLineWidth = targetWidth;
//     const double averageWordWidth = 45.0; // Estimated average word width
//     const int wordsPerLine = 6; // Estimated words per line
    
//     int currentWordIndex = 0;
    
//     while (currentWordIndex < words.length && lines.length < targetLines) {
//       final lineStartIndex = currentWordIndex;
//       int wordsInLine = 0;
//       double lineWidth = 0.0;
      
//       // Add words to line until we reach capacity or run out of words
//       while (currentWordIndex < words.length && 
//              wordsInLine < wordsPerLine && 
//              lineWidth < maxLineWidth) {
        
//         final word = words[currentWordIndex];
//         final wordWidth = _estimateWordWidth(word);
        
//         if (lineWidth + wordWidth <= maxLineWidth || wordsInLine == 0) {
//           lineWidth += wordWidth;
//           wordsInLine++;
//           currentWordIndex++;
//         } else {
//           break;
//         }
//       }
      
//       // Create line break
//       final lineBreak = LineBreak(
//         startWordIndex: lineStartIndex,
//         endWordIndex: currentWordIndex,
//         kashidaInsertions: [], // No kashida for simplified version
//         actualWidth: lineWidth,
//       );
      
//       lines.add(lineBreak);
//       print('🔥 MUSHAF_LAYOUT: Line ${lines.length}: words $lineStartIndex-$currentWordIndex (${wordsInLine} words)');
//     }
    
//     print('🔥 MUSHAF_LAYOUT: Simple line breaking completed: ${lines.length} lines');
//     return lines;
//   }

//   // ESTIMATE WORD WIDTH
//   double _estimateWordWidth(String word) {
//     // Simple estimation based on character count
//     return word.length * 12.0 + 10.0; // Base width per character + spacing
//   }

//   // CREATE EMPTY LAYOUT FALLBACK
//   List<LineBreak> _createEmptyLayout() {
//     print('🔥 MUSHAF_LAYOUT: Creating empty fallback layout');
    
//     return List.generate(targetLines, (index) {
//       return LineBreak(
//         startWordIndex: 0,
//         endWordIndex: 0,
//         kashidaInsertions: [],
//         actualWidth: 0.0,
//       );
//     });
//   }
// }

// // 4. SIMPLIFIED MUSHAF RENDERER
// class MushafRenderer {
//   final MushafLayoutEngine _layoutEngine = MushafLayoutEngine();

//   Future<List<LineBreak>> layoutPage(List<AyatData> ayatList) async {
//     print('🔥 MUSHAF_RENDERER: layoutPage called with ${ayatList.length} ayats');
//     return await _layoutEngine.layoutPage(ayatList);
//   }

//   Future<Widget> renderPage(List<AyatData> ayatList) async {
//     print('🔥 MUSHAF_RENDERER: renderPage called');
    
//     try {
//       final lineBreaks = await layoutPage(ayatList);
      
//       return Container(
//         width: MushafRenderingConstants.PAGE_WIDTH,
//         height: MushafRenderingConstants.PAGE_HEIGHT,
//         padding: const EdgeInsets.only(
//           left: MushafRenderingConstants.MARGIN_LEFT,
//           right: MushafRenderingConstants.MARGIN_RIGHT,
//         ),
//         child: Column(
//           children: lineBreaks.asMap().entries.map((entry) {
//             final lineIndex = entry.key;
//             final lineBreak = entry.value;
            
//             return SizedBox(
//               height: MushafRenderingConstants.LINE_HEIGHT,
//               child: _renderLine(lineBreak, lineIndex + 1, ayatList),
//             );
//           }).toList(),
//         ),
//       );
//     } catch (e, stackTrace) {
//       print('🔥 MUSHAF_RENDERER: ERROR in renderPage: $e');
//       print('🔥 MUSHAF_RENDERER: STACKTRACE: $stackTrace');
      
//       // Return error widget
//       return Container(
//         width: MushafRenderingConstants.PAGE_WIDTH,
//         height: MushafRenderingConstants.PAGE_HEIGHT,
//         child: Center(
//           child: Text(
//             'Layout Error: $e',
//             style: TextStyle(color: Colors.red, fontSize: 12),
//             textAlign: TextAlign.center,
//           ),
//         ),
//       );
//     }
//   }

//   Widget _renderLine(LineBreak lineBreak, int lineNumber, List<AyatData> ayatList) {
//     try {
//       final lineText = _buildLineText(lineBreak, ayatList);
      
//       return Container(
//         width: double.infinity,
//         height: MushafRenderingConstants.LINE_HEIGHT,
//         alignment: Alignment.centerRight,
//         child: Text(
//           lineText,
//           style: const TextStyle(
//             fontFamily: 'KFGQPCUthmanicScriptHAFSRegular',
//             fontSize: MushafRenderingConstants.BASE_FONT_SIZE,
//             height: 1.0,
//           ),
//           textDirection: TextDirection.rtl,
//           textAlign: TextAlign.justify,
//           overflow: TextOverflow.ellipsis,
//         ),
//       );
//     } catch (e) {
//       print('🔥 MUSHAF_RENDERER: ERROR in _renderLine: $e');
      
//       return Container(
//         width: double.infinity,
//         height: MushafRenderingConstants.LINE_HEIGHT,
//         alignment: Alignment.centerRight,
//         child: Text(
//           'Line $lineNumber - Error',
//           style: TextStyle(color: Colors.red, fontSize: 12),
//         ),
//       );
//     }
//   }

//   String _buildLineText(LineBreak lineBreak, List<AyatData> ayatList) {
//     try {
//       // Extract words for this line
//       final allWords = <String>[];
//       for (final ayat in ayatList) {
//         allWords.addAll(ayat.wordsArrayNt);
//       }
      
//       if (lineBreak.startWordIndex >= allWords.length || lineBreak.endWordIndex > allWords.length) {
//         return 'Line text unavailable';
//       }
      
//       final lineWords = allWords.sublist(lineBreak.startWordIndex, lineBreak.endWordIndex);
//       return lineWords.join(' ');
      
//     } catch (e) {
//       print('🔥 MUSHAF_RENDERER: ERROR in _buildLineText: $e');
//       return 'Text error';
//     }
//   }
// }
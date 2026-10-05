import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class CatValidationResult {
  final bool isCat;
  final double confidence;
  final String primaryLabel;
  final List<String> detectedLabels;
  final String message;

  const CatValidationResult({
    required this.isCat,
    required this.confidence,
    required this.primaryLabel,
    required this.detectedLabels,
    required this.message,
  });
}

class RescueActionValidationResult {
  final bool isValid;
  final bool isCat;
  final bool actionProofMatched;
  final double confidence;
  final String primaryLabel;
  final String matchedActionDetail;
  final List<String> detectedLabels;
  final String message;

  const RescueActionValidationResult({
    required this.isValid,
    required this.isCat,
    required this.actionProofMatched,
    required this.confidence,
    required this.primaryLabel,
    required this.matchedActionDetail,
    required this.detectedLabels,
    required this.message,
  });
}

class AiValidationService {

  static final Set<String> _feedingKeywords = {
    'food', 'pet food', 'cat food', 'bowl', 'dish', 'plate', 'tin', 'can',
    'saucer', 'eating', 'feed', 'meal', 'tableware', 'crockery', 'kitchen utensil',
    'spoon', 'fork', 'container', 'packaged goods', 'snack', 'drink', 'drinking',
    'water bowl', 'kibble', 'diet', 'dairy', 'milk', 'tuna', 'meat', 'fish',
  };

  static final Set<String> _vetKeywords = {
    'veterinary', 'clinic', 'hospital', 'medical', 'medicine', 'health care',
    'bandage', 'syringe', 'stethoscope', 'carrier', 'pet carrier', 'cage',
    'table', 'examination table', 'cone', 'collar', 'elizabethan collar',
    'doctor', 'nurse', 'pharmacy', 'treatment', 'sterile', 'gauze', 'gloves',
  };

  static final Set<String> _tookInKeywords = {
    'indoor', 'room', 'living room', 'bedroom', 'furniture', 'couch', 'sofa',
    'bed', 'blanket', 'cushion', 'pillow', 'towel', 'floor', 'rug', 'carpet',
    'cat bed', 'house', 'home', 'tile', 'wood flooring', 'curtain', 'quilt',
  };

  static final Set<String> _shelteredKeywords = {
    'cage', 'crate', 'carrier', 'pet carrier', 'kennel', 'enclosure', 'wire',
    'fence', 'fencing', 'shelter', 'pen', 'box', 'cardboard box', 'carton',
    'transport cage', 'travel carrier', 'animal shelter',
  };

  static final Set<String> _rehomedKeywords = {
    'person', 'human', 'hand', 'arm', 'lap', 'holding', 'hug', 'child',
    'indoor', 'room', 'furniture', 'home', 'family', 'smile', 'bed',
    'carrier', 'couch', 'sofa',
  };

  static final Set<String> _stillHereKeywords = {
    'outdoor', 'street', 'road', 'sidewalk', 'pavement', 'asphalt', 'ground',
    'grass', 'soil', 'plant', 'tree', 'building', 'wall', 'brick', 'concrete',
    'parking lot', 'alley', 'urban', 'neighborhood',
  };


  static final Set<String> _strictCatKeywords = {
    'cat',
    'kitten',
    'feline',
    'felidae',
    'tabby',
    'tabby cat',
    'domestic short-haired cat',
    'european shorthair',
    'aegean cat',
    'siamese cat',
    'persian cat',
    'maine coon',
    'ragdoll',
    'british shorthair',
    'bengal cat',
    'sphynx',
    'burmese cat',
    'abyssinian',
    'polydactyl cat',
    'dragon li',
    'asian semi-longhair',
    'calico',
    'tortoiseshell',
    'feral cat',
    'munchkin cat',
    'norwegian forest cat',
    'russian blue',
    'black cat',
    'whiskers',
  };


  static final Set<String> _syntheticKeywords = {
    'toy',
    'stuffed toy',
    'plush',
    'plushie',
    'doll',
    'puppet',
    'figurine',
    'action figure',
    'cartoon',
    'animated cartoon',
    'animation',
    'drawing',
    'illustration',
    'clip art',
    'graphics',
    'sketch',
    'anime',
  };


  static final Set<String> _screenRecaptureKeywords = {
    'computer monitor',
    'monitor',
    'display device',
    'television',
    'screen',
    'flat panel display',
    'laptop',
    'tablet computer',
    'lcd screen',
    'led display',
    'computer keyboard',
    'multimedia',
    'screenshot',
    'webpage',
  };


  static final Set<String> _nonCatSmallMammals = {
    'ferret',
    'weasel',
    'mustelid',
    'mustelidae',
    'badger',
    'otter',
    'mink',
    'stoat',
    'chinchilla',
    'hamster',
    'gerbil',
    'guinea pig',
    'degu',
    'meerkat',
    'mongoose',
    'opossum',
    'possum',
    'skunk',
    'hedgehog',
    'sugar glider',
    'rabbit',
    'bunny',
    'hare',
    'rabbits and hares',
    'domestic rabbit',
    'cottontail rabbit',
    'lagomorpha',
    'rodent',
    'squirrel',
    'mouse',
    'rat',
  };


  static final Set<String> _dogKeywords = {
    'dog',
    'puppy',
    'canine',
    'dog breed',
    'hound',
    'retriever',
    'bulldog',
    'terrier',
    'german shepherd',
    'poodle',
    'husky',
    'golden retriever',
    'labrador retriever',
  };


  static final Set<String> _rescueContextKeywords = {
    'box',
    'cardboard',
    'carton',
    'cage',
    'crate',
    'litter box',
    'paw',
    'fur',
    'snout',
    'eye',
    'ear',
    'mammal',
    'carnivore',
    'vertebrate',
    'terrestrial animal',
  };

  static const double _minCatConfidence = 0.38;

  Future<CatValidationResult> validateCatImage(File imageFile) async {
    ImageLabeler? labeler;
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final options = ImageLabelerOptions(confidenceThreshold: 0.25);
      labeler = ImageLabeler(options: options);

      final List<ImageLabel> labels = await labeler.processImage(inputImage);

      if (labels.isEmpty) {
        return const CatValidationResult(
          isCat: false,
          confidence: 0.0,
          primaryLabel: 'Unknown',
          detectedLabels: [],
          message: 'No recognizable objects found in this image.',
        );
      }

      final List<String> detectedNames = [];
      bool strictCatFound = false;
      bool syntheticFound = false;
      bool nonCatSmallMammalFound = false;
      bool dogFound = false;
      bool rescueContextFound = false;
      bool screenRecaptureFound = false;

      double highestCatConf = 0.0;
      double highestSyntheticConf = 0.0;
      double highestNonCatMammalConf = 0.0;
      double highestDogConf = 0.0;
      double highestScreenConf = 0.0;

      String matchedCatLabel = '';
      String matchedSyntheticLabel = '';
      String matchedNonCatMammalLabel = '';
      String matchedDogLabel = '';
      String matchedScreenLabel = '';

      for (final label in labels) {
        final textLower = label.label.toLowerCase().trim();
        detectedNames.add('${label.label} (${(label.confidence * 100).toStringAsFixed(0)}%)');


        for (final catKey in _strictCatKeywords) {
          if (textLower == catKey ||
              textLower.contains(catKey) ||
              (catKey.length > 4 && catKey.contains(textLower))) {
            strictCatFound = true;
            if (label.confidence > highestCatConf) {
              highestCatConf = label.confidence;
              matchedCatLabel = label.label;
            }
          }
        }


        for (final synthKey in _syntheticKeywords) {
          if (textLower == synthKey || textLower.contains(synthKey)) {
            syntheticFound = true;
            if (label.confidence > highestSyntheticConf) {
              highestSyntheticConf = label.confidence;
              matchedSyntheticLabel = label.label;
            }
          }
        }


        for (final mammalKey in _nonCatSmallMammals) {
          if (textLower == mammalKey || textLower.contains(mammalKey)) {
            nonCatSmallMammalFound = true;
            if (label.confidence > highestNonCatMammalConf) {
              highestNonCatMammalConf = label.confidence;
              matchedNonCatMammalLabel = label.label;
            }
          }
        }


        for (final dogKey in _dogKeywords) {
          if (textLower == dogKey || textLower.contains(dogKey)) {
            dogFound = true;
            if (label.confidence > highestDogConf) {
              highestDogConf = label.confidence;
              matchedDogLabel = label.label;
            }
          }
        }


        for (final screenKey in _screenRecaptureKeywords) {
          if (textLower == screenKey || textLower.contains(screenKey)) {
            screenRecaptureFound = true;
            if (label.confidence > highestScreenConf) {
              highestScreenConf = label.confidence;
              matchedScreenLabel = label.label;
            }
          }
        }


        for (final contextKey in _rescueContextKeywords) {
          if (textLower == contextKey || textLower.contains(contextKey)) {
            rescueContextFound = true;
          }
        }
      }


      if (screenRecaptureFound && highestScreenConf >= 0.55 && highestScreenConf > highestCatConf) {
        return CatValidationResult(
          isCat: false,
          confidence: highestScreenConf,
          primaryLabel: matchedScreenLabel,
          detectedLabels: detectedNames,
          message:
              'Photo appears to be taken of a computer/phone screen or monitor (Detected: $matchedScreenLabel 🖥️). Please upload a direct photo of the cat.',
        );
      }


      if (syntheticFound && highestSyntheticConf >= 0.40) {
        return CatValidationResult(
          isCat: false,
          confidence: highestSyntheticConf,
          primaryLabel: matchedSyntheticLabel,
          detectedLabels: detectedNames,
          message:
              'Please upload a photo of a real living cat (Detected: $matchedSyntheticLabel 🧸).',
        );
      }


      if (nonCatSmallMammalFound && (highestNonCatMammalConf >= 0.35 || highestNonCatMammalConf > highestCatConf)) {
        return CatValidationResult(
          isCat: false,
          confidence: highestNonCatMammalConf,
          primaryLabel: matchedNonCatMammalLabel,
          detectedLabels: detectedNames,
          message:
              'PawWatch is for cats only! (Detected: $matchedNonCatMammalLabel 🐾). Please upload a cat photo.',
        );
      }


      if (dogFound && !strictCatFound && highestDogConf >= 0.45) {
        return CatValidationResult(
          isCat: false,
          confidence: highestDogConf,
          primaryLabel: matchedDogLabel,
          detectedLabels: detectedNames,
          message:
              'PawWatch is cat-specific! (Detected: $matchedDogLabel 🐶). Please upload a cat photo 🐾',
        );
      }


      if (strictCatFound && (highestCatConf >= _minCatConfidence || (rescueContextFound && highestCatConf >= 0.30))) {
        return CatValidationResult(
          isCat: true,
          confidence: highestCatConf > 0 ? highestCatConf : 0.85,
          primaryLabel: matchedCatLabel.isNotEmpty ? matchedCatLabel : 'Cat',
          detectedLabels: detectedNames,
          message: 'Cat successfully verified! 🐾',
        );
      }


      final topDetections = labels.take(3).map((l) => l.label).join(', ');
      return CatValidationResult(
        isCat: false,
        confidence: labels.first.confidence,
        primaryLabel: labels.first.label,
        detectedLabels: detectedNames,
        message:
            'No cat detected (Detected: $topDetections). Please upload a clear photo of a cat.',
      );
    } catch (e) {
      return CatValidationResult(
        isCat: false,
        confidence: 0.0,
        primaryLabel: 'Error',
        detectedLabels: [],
        message: 'AI scanning error: ${e.toString()}',
      );
    } finally {
      labeler?.close();
    }
  }


  Future<RescueActionValidationResult> validateRescueActionProof(
      File imageFile, String action) async {
    ImageLabeler? labeler;
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final options = ImageLabelerOptions(confidenceThreshold: 0.18);
      labeler = ImageLabeler(options: options);

      final List<ImageLabel> labels = await labeler.processImage(inputImage);

      if (labels.isEmpty) {
        return const RescueActionValidationResult(
          isValid: false,
          isCat: false,
          actionProofMatched: false,
          confidence: 0.0,
          primaryLabel: 'Unknown',
          matchedActionDetail: '',
          detectedLabels: [],
          message:
              'No recognizable objects found in this image. Please take a clear photo.',
        );
      }

      final List<String> detectedNames = [];
      bool strictCatFound = false;
      bool syntheticFound = false;
      bool nonCatSmallMammalFound = false;
      bool dogFound = false;
      bool rescueContextFound = false;
      bool screenRecaptureFound = false;

      double highestCatConf = 0.0;
      double highestSyntheticConf = 0.0;
      double highestNonCatMammalConf = 0.0;
      double highestDogConf = 0.0;
      double highestScreenConf = 0.0;

      String matchedCatLabel = '';
      String matchedSyntheticLabel = '';
      String matchedNonCatMammalLabel = '';
      String matchedDogLabel = '';
      String matchedScreenLabel = '';


      bool actionCuesFound = false;
      String matchedActionCue = '';

      Set<String> targetActionSet;
      String actionName;
      String actionIcon;
      switch (action) {
        case 'fed':
          targetActionSet = _feedingKeywords;
          actionName = 'Food/Bowl';
          actionIcon = '🥣';
          break;
        case 'vet':
          targetActionSet = _vetKeywords;
          actionName = 'Medical/Clinic';
          actionIcon = '🩺';
          break;
        case 'tookIn':
          targetActionSet = _tookInKeywords;
          actionName = 'Indoor Care';
          actionIcon = '🏠';
          break;
        case 'sheltered':
          targetActionSet = _shelteredKeywords;
          actionName = 'Shelter/Carrier';
          actionIcon = '🐾';
          break;
        case 'rehomed':
          targetActionSet = _rehomedKeywords;
          actionName = 'Adopter/Home';
          actionIcon = '💖';
          break;
        case 'stillHere':
        default:
          targetActionSet = _stillHereKeywords;
          actionName = 'Environment';
          actionIcon = '📍';
          break;
      }

      for (final label in labels) {
        final textLower = label.label.toLowerCase().trim();
        detectedNames.add(
            '${label.label} (${(label.confidence * 100).toStringAsFixed(0)}%)');


        for (final catKey in _strictCatKeywords) {
          if (textLower == catKey ||
              textLower.contains(catKey) ||
              (catKey.length > 4 && catKey.contains(textLower))) {
            strictCatFound = true;
            if (label.confidence > highestCatConf) {
              highestCatConf = label.confidence;
              matchedCatLabel = label.label;
            }
          }
        }


        for (final synthKey in _syntheticKeywords) {
          if (textLower == synthKey || textLower.contains(synthKey)) {
            syntheticFound = true;
            if (label.confidence > highestSyntheticConf) {
              highestSyntheticConf = label.confidence;
              matchedSyntheticLabel = label.label;
            }
          }
        }


        for (final mammalKey in _nonCatSmallMammals) {
          if (textLower == mammalKey || textLower.contains(mammalKey)) {
            nonCatSmallMammalFound = true;
            if (label.confidence > highestNonCatMammalConf) {
              highestNonCatMammalConf = label.confidence;
              matchedNonCatMammalLabel = label.label;
            }
          }
        }


        for (final dogKey in _dogKeywords) {
          if (textLower == dogKey || textLower.contains(dogKey)) {
            dogFound = true;
            if (label.confidence > highestDogConf) {
              highestDogConf = label.confidence;
              matchedDogLabel = label.label;
            }
          }
        }


        for (final screenKey in _screenRecaptureKeywords) {
          if (textLower == screenKey || textLower.contains(screenKey)) {
            screenRecaptureFound = true;
            if (label.confidence > highestScreenConf) {
              highestScreenConf = label.confidence;
              matchedScreenLabel = label.label;
            }
          }
        }


        for (final contextKey in _rescueContextKeywords) {
          if (textLower == contextKey || textLower.contains(contextKey)) {
            rescueContextFound = true;
          }
        }


        for (final actionKey in targetActionSet) {
          if (textLower == actionKey || textLower.contains(actionKey)) {
            actionCuesFound = true;
            matchedActionCue = label.label;
          }
        }
      }


      if (screenRecaptureFound && highestScreenConf >= 0.55 && highestScreenConf > highestCatConf) {
        return RescueActionValidationResult(
          isValid: false,
          isCat: false,
          actionProofMatched: false,
          confidence: highestScreenConf,
          primaryLabel: matchedScreenLabel,
          matchedActionDetail: '',
          detectedLabels: detectedNames,
          message:
              'Photo appears to be taken of a computer/phone screen ($matchedScreenLabel 🖥️). Please upload a direct photo of the cat.',
        );
      }


      if (syntheticFound && highestSyntheticConf >= 0.38) {
        return RescueActionValidationResult(
          isValid: false,
          isCat: false,
          actionProofMatched: false,
          confidence: highestSyntheticConf,
          primaryLabel: matchedSyntheticLabel,
          matchedActionDetail: '',
          detectedLabels: detectedNames,
          message:
              'Photo shows a toy or synthetic cat ($matchedSyntheticLabel 🧸). Real living cat proof required.',
        );
      }


      if (nonCatSmallMammalFound &&
          (highestNonCatMammalConf >= 0.35 ||
              highestNonCatMammalConf > highestCatConf)) {
        return RescueActionValidationResult(
          isValid: false,
          isCat: false,
          actionProofMatched: false,
          confidence: highestNonCatMammalConf,
          primaryLabel: matchedNonCatMammalLabel,
          matchedActionDetail: '',
          detectedLabels: detectedNames,
          message:
              'Proof rejected: Detected $matchedNonCatMammalLabel instead of a cat 🐾.',
        );
      }


      if (dogFound && !strictCatFound && highestDogConf >= 0.45) {
        return RescueActionValidationResult(
          isValid: false,
          isCat: false,
          actionProofMatched: false,
          confidence: highestDogConf,
          primaryLabel: matchedDogLabel,
          matchedActionDetail: '',
          detectedLabels: detectedNames,
          message:
              'Proof rejected: Detected $matchedDogLabel 🐶. PawWatch is cat-specific.',
        );
      }


      final isCatVerified = strictCatFound &&
          (highestCatConf >= 0.30 ||
              (rescueContextFound && highestCatConf >= 0.25));

      if (!isCatVerified) {
        final topDetections = labels.take(3).map((l) => l.label).join(', ');
        return RescueActionValidationResult(
          isValid: false,
          isCat: false,
          actionProofMatched: actionCuesFound,
          confidence: labels.first.confidence,
          primaryLabel: labels.first.label,
          matchedActionDetail: matchedActionCue,
          detectedLabels: detectedNames,
          message:
              'No cat detected in photo (Detected: $topDetections). Please capture the cat clearly in your proof.',
        );
      }


      final detail = actionCuesFound
          ? '$actionName detected ($matchedActionCue)'
          : '$matchedCatLabel in rescue scene';

      final successMsg = actionCuesFound
          ? '✨ Action verified! Cat + $actionName detected ($matchedActionCue) $actionIcon'
          : '✨ Living cat verified! ($matchedCatLabel 🐾)';

      return RescueActionValidationResult(
        isValid: true,
        isCat: true,
        actionProofMatched: actionCuesFound,
        confidence: highestCatConf > 0 ? highestCatConf : 0.85,
        primaryLabel: matchedCatLabel.isNotEmpty ? matchedCatLabel : 'Cat',
        matchedActionDetail: detail,
        detectedLabels: detectedNames,
        message: successMsg,
      );
    } catch (e) {
      return RescueActionValidationResult(
        isValid: false,
        isCat: false,
        actionProofMatched: false,
        confidence: 0.0,
        primaryLabel: 'Error',
        matchedActionDetail: '',
        detectedLabels: [],
        message: 'AI scanning error: ${e.toString()}',
      );
    } finally {
      labeler?.close();
    }
  }
}



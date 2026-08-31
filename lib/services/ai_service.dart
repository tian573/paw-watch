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
  // Action-specific proof visual keywords
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

  // Pure feline keywords (Exact cat/kitten/feline breeds)
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

  // Synthetic / Non-living cat objects (Plushies, Cartoon, Drawings, Dolls)
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

  // Specific Non-Cat Small Mammals (Ferrets, Weasels, Rodents, Rabbits)
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

  // Distinct Canines (Dogs/Puppies)
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

  // Contextual rescue indicators that give boost to cat verification
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

      double highestCatConf = 0.0;
      double highestSyntheticConf = 0.0;
      double highestNonCatMammalConf = 0.0;
      double highestDogConf = 0.0;

      String matchedCatLabel = '';
      String matchedSyntheticLabel = '';
      String matchedNonCatMammalLabel = '';
      String matchedDogLabel = '';

      for (final label in labels) {
        final textLower = label.label.toLowerCase().trim();
        detectedNames.add('${label.label} (${(label.confidence * 100).toStringAsFixed(0)}%)');

        // 1. Strict Feline Check
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

        // 2. Synthetic (Toy, Cartoon, Plush)
        for (final synthKey in _syntheticKeywords) {
          if (textLower == synthKey || textLower.contains(synthKey)) {
            syntheticFound = true;
            if (label.confidence > highestSyntheticConf) {
              highestSyntheticConf = label.confidence;
              matchedSyntheticLabel = label.label;
            }
          }
        }

        // 3. Non-Cat Small Mammals (Ferret, Hamster, Rabbit)
        for (final mammalKey in _nonCatSmallMammals) {
          if (textLower == mammalKey || textLower.contains(mammalKey)) {
            nonCatSmallMammalFound = true;
            if (label.confidence > highestNonCatMammalConf) {
              highestNonCatMammalConf = label.confidence;
              matchedNonCatMammalLabel = label.label;
            }
          }
        }

        // 4. Dogs
        for (final dogKey in _dogKeywords) {
          if (textLower == dogKey || textLower.contains(dogKey)) {
            dogFound = true;
            if (label.confidence > highestDogConf) {
              highestDogConf = label.confidence;
              matchedDogLabel = label.label;
            }
          }
        }

        // 5. Rescue Context (Box, Cardboard, Fur, Ear)
        for (final contextKey in _rescueContextKeywords) {
          if (textLower == contextKey || textLower.contains(contextKey)) {
            rescueContextFound = true;
          }
        }
      }

      // Check 1: Reject Synthetic / Toys / Cartoons
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

      // Check 2: Reject Ferrets / Hamsters / Rabbits
      // Even if generic 'whiskers' or 'mammal' is present, if ferret/hamster is identified, reject it!
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

      // Check 3: Reject Clear Dogs (Unless cat/kitten is also detected in rescue context like black kittens in box)
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

      // Check 4: Success on Feline Match (Supports black kittens in cardboard boxes, rescue angles)
      if (strictCatFound && (highestCatConf >= _minCatConfidence || (rescueContextFound && highestCatConf >= 0.30))) {
        return CatValidationResult(
          isCat: true,
          confidence: highestCatConf > 0 ? highestCatConf : 0.85,
          primaryLabel: matchedCatLabel.isNotEmpty ? matchedCatLabel : 'Cat',
          detectedLabels: detectedNames,
          message: 'Cat successfully verified! 🐾',
        );
      }

      // Fallback: No cat found
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

  /// Verifies both the presence of a living cat AND action-specific proof (e.g. food/bowl for feeding, clinic for vet, carrier for shelter)
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

      double highestCatConf = 0.0;
      double highestSyntheticConf = 0.0;
      double highestNonCatMammalConf = 0.0;
      double highestDogConf = 0.0;

      String matchedCatLabel = '';
      String matchedSyntheticLabel = '';
      String matchedNonCatMammalLabel = '';
      String matchedDogLabel = '';

      // Action-specific matching
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

        // 1. Strict Feline Check
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

        // 2. Synthetic (Toy, Cartoon, Plush)
        for (final synthKey in _syntheticKeywords) {
          if (textLower == synthKey || textLower.contains(synthKey)) {
            syntheticFound = true;
            if (label.confidence > highestSyntheticConf) {
              highestSyntheticConf = label.confidence;
              matchedSyntheticLabel = label.label;
            }
          }
        }

        // 3. Non-Cat Small Mammals
        for (final mammalKey in _nonCatSmallMammals) {
          if (textLower == mammalKey || textLower.contains(mammalKey)) {
            nonCatSmallMammalFound = true;
            if (label.confidence > highestNonCatMammalConf) {
              highestNonCatMammalConf = label.confidence;
              matchedNonCatMammalLabel = label.label;
            }
          }
        }

        // 4. Dogs
        for (final dogKey in _dogKeywords) {
          if (textLower == dogKey || textLower.contains(dogKey)) {
            dogFound = true;
            if (label.confidence > highestDogConf) {
              highestDogConf = label.confidence;
              matchedDogLabel = label.label;
            }
          }
        }

        // 5. Rescue Context
        for (final contextKey in _rescueContextKeywords) {
          if (textLower == contextKey || textLower.contains(contextKey)) {
            rescueContextFound = true;
          }
        }

        // 6. Action-specific match
        for (final actionKey in targetActionSet) {
          if (textLower == actionKey || textLower.contains(actionKey)) {
            actionCuesFound = true;
            matchedActionCue = label.label;
          }
        }
      }

      // Check 1: Reject Synthetic / Toys / Cartoons
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
              'Fake proof rejected: Detected toy/cartoon/plush ($matchedSyntheticLabel 🧸). Real living cat proof is required.',
        );
      }

      // Check 2: Reject Non-Cat Animals
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

      // Check 3: Reject Clear Dogs
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

      // Check 4: Cat verification
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

      // Check 5: Action proof matched
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

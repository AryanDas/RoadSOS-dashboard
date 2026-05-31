import 'dart:convert';
import 'package:flutter/services.dart';

class DecisionNode {
  final int feature;
  final double threshold;
  final List<double>? value;
  final DecisionNode? left;
  final DecisionNode? right;

  DecisionNode({
    required this.feature,
    required this.threshold,
    this.value,
    this.left,
    this.right,
  });

  factory DecisionNode.fromJson(Map<String, dynamic> json) {
    if (json['feature'] == -1) {
      final List<dynamic> valList = json['value'];
      return DecisionNode(
        feature: -1,
        threshold: 0.0,
        value: valList.map((e) => (e as num).toDouble()).toList(),
      );
    }
    return DecisionNode(
      feature: json['feature'] as int,
      threshold: (json['threshold'] as num).toDouble(),
      left: DecisionNode.fromJson(json['left'] as Map<String, dynamic>),
      right: DecisionNode.fromJson(json['right'] as Map<String, dynamic>),
    );
  }

  double predict(List<double> features) {
    if (feature == -1) {
      final sum = value![0] + value![1];
      if (sum == 0) return 0.0;
      return value![1] / sum; // Probability of class 1 (Crash)
    }
    if (features[feature] <= threshold) {
      return left!.predict(features);
    } else {
      return right!.predict(features);
    }
  }
}

class RandomForestClassifier {
  final int nEstimators;
  final int nFeatures;
  final List<DecisionNode> trees;

  RandomForestClassifier({
    required this.nEstimators,
    required this.nFeatures,
    required this.trees,
  });

  factory RandomForestClassifier.fromJson(Map<String, dynamic> json) {
    final treesList = (json['trees'] as List)
        .map((e) => DecisionNode.fromJson(e as Map<String, dynamic>))
        .toList();
    return RandomForestClassifier(
      nEstimators: json['n_estimators'] as int,
      nFeatures: json['n_features'] as int,
      trees: treesList,
    );
  }

  static Future<RandomForestClassifier> loadFromAssets(String path) async {
    final jsonStr = await rootBundle.loadString(path);
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    return RandomForestClassifier.fromJson(data);
  }

  double predictProbability(List<double> features) {
    double totalProb = 0.0;
    for (final tree in trees) {
      totalProb += tree.predict(features);
    }
    return totalProb / nEstimators;
  }

  bool isCrash(List<double> features, {double threshold = 0.65}) {
    final prob = predictProbability(features);
    return prob >= threshold;
  }
}

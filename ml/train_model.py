import os
import json
import numpy as np
from sklearn.ensemble import RandomForestClassifier

def generate_synthetic_data(num_samples=1200):
    """
    Generates synthetic sensor feature vectors of shape (num_samples, 44)
    to simulate crash (class 1) and non-crash (class 0) scenarios.
    """
    np.random.seed(42)
    features = []
    labels = []
    
    # Class 0: Non-crash (normal driving, walking, running, minor bumps, sudden braking)
    num_non_crash = num_samples // 2
    for _ in range(num_non_crash):
        acc_means = np.random.normal(loc=9.8, scale=1.5, size=4)
        gyro_means = np.random.normal(loc=0.0, scale=0.5, size=4)
        acc_stds = np.random.uniform(0.1, 0.8, size=4)
        gyro_stds = np.random.uniform(0.05, 0.3, size=4)
        acc_vars = acc_stds ** 2
        gyro_vars = gyro_stds ** 2
        acc_maxs = acc_means + np.random.uniform(0.5, 2.0, size=4)
        gyro_maxs = gyro_means + np.random.uniform(0.1, 1.0, size=4)
        acc_mins = acc_means - np.random.uniform(0.5, 2.0, size=4)
        gyro_mins = gyro_means - np.random.uniform(0.1, 1.0, size=4)
        acc_range = acc_maxs[3] - acc_mins[3]
        gyro_range = gyro_maxs[3] - gyro_mins[3]
        curr_acc = np.random.normal(loc=9.8, scale=1.0)
        curr_gyro = np.random.normal(loc=0.1, scale=0.2)
        
        vector = np.concatenate([
            acc_means, gyro_means, acc_stds, gyro_stds,
            acc_vars, gyro_vars, acc_maxs, gyro_maxs,
            acc_mins, gyro_mins, [acc_range, gyro_range],
            [curr_acc, curr_gyro]
        ])
        features.append(vector)
        labels.append(0)

    # Class 1: Crash (sudden massive deceleration, rolling/tumbling)
    num_crash = num_samples - num_non_crash
    for _ in range(num_crash):
        acc_means = np.random.normal(loc=28.0, scale=10.0, size=4)
        gyro_means = np.random.normal(loc=8.0, scale=4.0, size=4)
        acc_stds = np.random.uniform(5.0, 15.0, size=4)
        gyro_stds = np.random.uniform(2.0, 8.0, size=4)
        acc_vars = acc_stds ** 2
        gyro_vars = gyro_stds ** 2
        acc_maxs = acc_means + np.random.uniform(15.0, 45.0, size=4)
        gyro_maxs = gyro_means + np.random.uniform(5.0, 20.0, size=4)
        acc_mins = acc_means - np.random.uniform(10.0, 20.0, size=4)
        gyro_mins = gyro_means - np.random.uniform(3.0, 10.0, size=4)
        acc_range = acc_maxs[3] - acc_mins[3]
        gyro_range = gyro_maxs[3] - gyro_mins[3]
        curr_acc = np.random.normal(loc=35.0, scale=8.0)
        curr_gyro = np.random.normal(loc=12.0, scale=3.0)
        
        vector = np.concatenate([
            acc_means, gyro_means, acc_stds, gyro_stds,
            acc_vars, gyro_vars, acc_maxs, gyro_maxs,
            acc_mins, gyro_mins, [acc_range, gyro_range],
            [curr_acc, curr_gyro]
        ])
        features.append(vector)
        labels.append(1)
        
    return np.array(features, dtype=np.float32), np.array(labels, dtype=np.int32)

def serialize_tree(tree_model, node_id=0):
    """
    Recursively serializes a decision tree from scikit-learn's Tree structure.
    """
    left_child = tree_model.children_left[node_id]
    right_child = tree_model.children_right[node_id]
    
    # Check if leaf node
    if left_child == -1 and right_child == -1:
        # leaf value represents class count distributions
        val = tree_model.value[node_id][0].tolist()
        return {
            "feature": -1,
            "threshold": 0.0,
            "value": val # List of weights for class 0 and 1
        }
    
    return {
        "feature": int(tree_model.feature[node_id]),
        "threshold": float(tree_model.threshold[node_id]),
        "left": serialize_tree(tree_model, left_child),
        "right": serialize_tree(tree_model, right_child)
    }

def train_and_export():
    print("Generating synthetic 44-dimensional sensor window datasets...")
    X, y = generate_synthetic_data(1500)
    
    # Shuffle
    indices = np.arange(X.shape[0])
    np.random.shuffle(indices)
    X, y = X[indices], y[indices]
    
    # Fit Random Forest
    print("Training Random Forest Classifier (10 Estimators, Max Depth 5 for Edge Performance)...")
    clf = RandomForestClassifier(n_estimators=10, max_depth=5, random_state=42)
    clf.fit(X, y)
    
    # Verify training accuracy
    train_acc = clf.score(X, y)
    print(f"Random Forest Training Accuracy: {train_acc * 100:.2f}%")
    
    # Serialize all trees in the ensemble
    forest_data = {
        "n_estimators": len(clf.estimators_),
        "n_features": int(clf.n_features_in_),
        "trees": [serialize_tree(tree.tree_) for tree in clf.estimators_]
    }
    
    # Output to Flutter Assets folder
    out_path = "../mobile/assets/models/crash_detector_rf.json"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(forest_data, f, indent=2)
    
    print(f"Successfully serialized and saved Random Forest model JSON to {out_path}")

if __name__ == "__main__":
    train_and_export()

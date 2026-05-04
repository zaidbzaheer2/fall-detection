import joblib
import onnx
from onnxmltools import convert_lightgbm
from onnxmltools.convert.common.data_types import FloatTensorType

# 1. Load and unwrap
search_result = joblib.load('Models/lgbm_model.joblib')
best_model = search_result.best_estimator_

# 2. Input shape
num_features = best_model.n_features_in_
initial_type = [('float_input', FloatTensorType([None, num_features]))]

# 3. Convert using onnxmltools directly — NOT convert_sklearn
onx = convert_lightgbm(
    best_model,
    initial_types=initial_type,
    target_opset=12
)

# 4. Save
output_path = "Models/lgbm_model.onnx"
onnx.save_model(onx, output_path)
print(f"✅ Success! ONNX model saved to: {output_path}")
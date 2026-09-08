import json
import os
import re

base_dir = r"C:\Users\Dhruv\.gemini\antigravity-ide\brain\a5fbb340-2e0b-4e19-afe0-161ed383b353\.system_generated\steps"

def extract_json(step_id):
    path = os.path.join(base_dir, str(step_id), "output.txt")
    with open(path, "r", encoding="utf-8") as f:
        wrapper = json.load(f)
    content = wrapper.get("result", "")
    
    # parse out the untrusted data boundary
    start = content.find("[{")
    end = content.rfind("}]") + 2
    if start != -1 and end > start:
        raw_json_str = content[start:end]
        print(f"Step {step_id}: extracted slice len={len(raw_json_str)}, start={raw_json_str[:30]!r} ... end={raw_json_str[-30:]!r}")
        data = json.loads(raw_json_str)
        return data
    else:
        raise ValueError(f"No JSON array found in step {step_id}")

print("Extracting day log slices...")
all_day_logs = []
for step_id in [8209, 8211, 8213, 8215, 8217]:
    rows = extract_json(step_id)
    # rows is [{'json_agg': [...]}]
    slice_data = rows[0]["json_agg"]
    if slice_data:
        all_day_logs.extend(slice_data)
        print(f"Step {step_id}: extracted {len(slice_data)} logs")

print(f"Total day logs extracted: {len(all_day_logs)}")

# Extract overrides
print("Extracting overrides from step 8219...")
overrides_rows = extract_json(8219)
overrides = overrides_rows[0]["json_agg"]
print(f"Total overrides extracted: {len(overrides)}")

# Extract profile and split from step 8187
print("Extracting profile and split from step 8187...")
meta_rows = extract_json(8187)
meta_obj = meta_rows[0]["jsonb_build_object"]
profile = meta_obj["profile"]
workout_split = meta_obj["workout_split"]

fixture = {
    "user_id": "ff27ad41-1c6d-4f22-aa27-84ceb9a2a344",
    "day_logs_count": len(all_day_logs),
    "day_logs": all_day_logs,
    "user_nutrition_memory_count": len(overrides),
    "user_nutrition_memory": overrides,
    "workout_split": workout_split,
    "profile": profile,
}

out_dir = r"c:\Users\Dhruv\Desktop\Kynetix\kynetix_ui\test\fixtures"
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "dhruv_real_history.json")

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(fixture, f, indent=2)

print(f"Successfully assembled real fixture at {out_path} ({os.path.getsize(out_path)} bytes)")

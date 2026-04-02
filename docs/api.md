# API / Estimation Contract

## Purpose
Define the expected request/response shape for meal estimation and related nutrition intelligence outputs.

This contract is designed for:
- natural language meal estimation
- realistic calorie/protein output
- confidence-aware UX
- future extensibility

---

# 1. Meal Estimation Request

## Minimal Request
```json
{
  "meal": "2 roti + dal + paneer"
}
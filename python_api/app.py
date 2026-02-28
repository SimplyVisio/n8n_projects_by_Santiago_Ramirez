import os
from fastapi import FastAPI, Request, Header, HTTPException

app = FastAPI(title="n8n Python API", version="1.0")

API_KEY = os.getenv("PYTHON_API_KEY")


@app.post("/test")
async def test(request: Request, x_api_key: str = Header(None, alias="x-api-key")):
    if not API_KEY:
        raise HTTPException(status_code=500, detail="API key not configured")
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    body = await request.json()
    return {"status": "ok", "received": body}


@app.get("/health")
def health():
    return {"status": "healthy"}


# 🔥 Nuevo endpoint para probar pandas y numpy
@app.get("/test-pandas")
def test_pandas(x_api_key: str = Header(None, alias="x-api-key")):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    import pandas as pd
    import numpy as np

    df = pd.DataFrame({
        "a": [1, 2, 3],
        "b": np.array([4, 5, 6])
    })

    return {
        "rows": len(df),
        "sum_a": int(df["a"].sum()),
        "numpy_version": np.__version__
    }
    

# 🔥 Nuevo endpoint  calculo score-lead
@app.post("/score-lead")
async def score_lead(data: dict, x_api_key: str = Header(None, alias="x-api-key")):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")

    import pandas as pd
    import numpy as np

    # Convert input to DataFrame
    df = pd.DataFrame([data])

    # Fill missing values
    df.fillna(0, inplace=True)

    # Normalize values between 0-100
    budget = np.clip(df.get("budget", 0), 0, 100)
    company_size = np.clip(df.get("company_size", 0), 0, 100)
    engagement = np.clip(df.get("engagement_level", 0), 0, 100)

    # Weighted scoring model
    score = (
        budget * 0.4 +
        company_size * 0.3 +
        engagement * 0.3
    )

    final_score = float(score.iloc[0])

    if final_score > 70:
        label = "Hot"
    elif final_score > 40:
        label = "Warm"
    else:
        label = "Cold"

    # Extra analytics (para impresionar reclutadores)
    stats = {
        "mean_input": float(np.mean([budget.iloc[0], company_size.iloc[0], engagement.iloc[0]])),
        "std_dev_input": float(np.std([budget.iloc[0], company_size.iloc[0], engagement.iloc[0]]))
    }

    return {
        "lead_score": round(final_score, 2),
        "classification": label,
        "analytics": stats
    }

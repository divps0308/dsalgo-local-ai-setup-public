FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends git curl grep findutils sed coreutils && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN useradd --create-home --uid 10001 agent && mkdir -p /workspace && chown -R agent:agent /app /workspace
USER agent
EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]

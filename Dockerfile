FROM python:3.12-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1 EDU_DATA_DIR=/app/data
COPY backend.py run.py reset_admin.py ./
COPY static ./static
COPY seed ./seed
COPY downloads ./downloads
RUN mkdir -p /app/data && chown -R 10001:10001 /app
USER 10001:10001
VOLUME ["/app/data"]
EXPOSE 8000
CMD ["python", "run.py", "--host", "0.0.0.0", "--port", "8000"]

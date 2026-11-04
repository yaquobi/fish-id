# قياس BioCLIP على المعالج (بدون كرت شاشة): bash server/eval.sh bioclip
# ونفس الصورة تشغّل خدمة بصمة في الظل (serve.py) من docker-compose.
FROM python:3.12-slim
RUN pip install --no-cache-dir torch==2.14.1 torchvision==0.29.1 --index-url https://download.pytorch.org/whl/cpu \
 && pip install --no-cache-dir open_clip_torch==3.3.0 pillow==13.0.0 "rembg[cpu]==2.0.86"
WORKDIR /app
COPY bench/bioclip/run.py /app/run.py
COPY bench/bioclip/serve.py /app/serve.py
COPY assets/data/ksafish.json /app/data/ksafish.json
# النموذج ينحمّل أول مرة من Hugging Face وينحفظ هنا (مربوط بـ data/hf على السيرفر).
ENV HF_HOME=/hf
# نماذج قص الخلفية (rembg) تنحفظ مع نماذج Hugging Face.
ENV U2NET_HOME=/hf/rembg
ENTRYPOINT ["python", "/app/run.py"]

# قياس BioCLIP 2 على المعالج (بدون كرت شاشة). يُبنى ويشتغل من bash server/eval.sh bioclip
FROM python:3.12-slim
RUN pip install --no-cache-dir torch==2.14.1 torchvision==0.29.1 --index-url https://download.pytorch.org/whl/cpu \
 && pip install --no-cache-dir open_clip_torch==3.3.0 pillow==13.0.0
WORKDIR /app
COPY bench/bioclip/run.py /app/run.py
COPY assets/data/ksafish.json /app/data/ksafish.json
# النموذج ينحمّل أول مرة من Hugging Face وينحفظ هنا (مربوط بـ data/hf على السيرفر).
ENV HF_HOME=/hf
ENTRYPOINT ["python", "/app/run.py"]

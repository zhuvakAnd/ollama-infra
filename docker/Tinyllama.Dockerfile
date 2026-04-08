FROM ollama/ollama:latest

RUN bash -c "ollama serve & \
             sleep 10 && \
             ollama pull tinyllama && \
             pkill ollama"

EXPOSE 11434
CMD ["ollama", "serve"]
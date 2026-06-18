FROM ollama/ollama:latest
#test trigger
RUN bash -lc '\
    ollama serve & \
    pid=$!; \
    for i in $(seq 1 60); do \
      ollama list >/dev/null 2>&1 && break; \
      sleep 1; \
    done; \
    ollama pull tinyllama; \
    kill $pid; \
    wait $pid || true \
'

EXPOSE 11434
CMD ["serve"]
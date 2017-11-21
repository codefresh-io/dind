FROM docker:17.06.0-ce-dind

COPY . /

CMD ["run.sh"]

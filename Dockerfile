FROM node:latest

WORKDIR /app

COPY . .

RUN npm install

EXPOSE 3000
EXPOSE 22

CMD ["node", "server.js"]

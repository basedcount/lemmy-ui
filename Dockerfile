FROM node:20.2-alpine as builder
RUN apk update && apk add curl yarn python3 build-base gcc wget git --no-cache
RUN curl -sf https://gobinaries.com/tj/node-prune | sh

WORKDIR /usr/src/app

ENV npm_config_target_arch=x64
ENV npm_config_target_platform=linux
ENV npm_config_target_libc=musl

# Cache deps
COPY package.json yarn.lock ./
RUN yarn --production --prefer-offline --pure-lockfile

# Build
COPY generate_translations.js \
  tsconfig.json \
  webpack.config.js \
  .babelrc \
  ./

COPY lemmy-translations lemmy-translations
COPY src src
COPY .git .git

# Set UI version 
RUN echo "export const VERSION = 'Kaleidoscope $(git describe --tag)';" > "src/shared/version.ts"

RUN yarn --production --prefer-offline
RUN NODE_OPTIONS="--max-old-space-size=8192" yarn build:prod

# Prune the image
RUN node-prune /usr/src/app/node_modules

RUN rm -rf ./node_modules/import-sort-parser-typescript
RUN rm -rf ./node_modules/typescript
RUN rm -rf ./node_modules/npm

RUN du -sh ./node_modules/* | sort -nr | grep '\dM.*'

FROM node:alpine as runner
COPY --from=builder /usr/src/app/dist /app/dist
COPY --from=builder /usr/src/app/node_modules /app/node_modules

# Copy the script
COPY inject-env.sh /app/inject-env.sh
# Make it executable
RUN chmod +x /app/inject-env.sh

RUN chown -R node:node /app

USER node
EXPOSE 1234
WORKDIR /app
CMD /app/inject-env.sh && node dist/js/server.js

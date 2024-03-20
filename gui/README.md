# snartomo-gui

Gui project for snartomo

## Project Setup

```sh
npm install
```

## Compile and Hot-Reload for Development

```sh
npm run dev
```

## Type-Check, Compile and Minify for Production

```sh
npm run build
```

After modifying the source code, it's necessary to build the project and then replace the content of the `docs` directory with that from the `dist` directory. The `github.io` website uses the `docs` directory for publishing.

## Managing Updates

After modifying the source code, you need to build the project and then replace the content of the `docs` directory with that of the `dist` directory. The `github.io` website uses the `docs` directory for publishing.

If you only need to update help information, make sure to update the corresponding files(`*-help.txt`) in both the `public` and `docs` directories simultaneously. The update in the `docs` directory will be published, while the update in the `public` directory prevents the accidental replacement of old help information after modifying the code.


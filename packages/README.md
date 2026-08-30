# Binhost overlay (packages/)

This directory is the **full binary package cache** that `gentoo-ing` consumes.

Drop Gentoo binary packages (`.tbz2`) here — that is the "plop in newer
packages" workflow. Preserve the layout the official binhost uses so images
look the same on disk:

```
packages/
├── sys-kernel/
│   └── gentoo-kernel-bin-6.14_rc4_p4.tbz2
├── app-containers/
│   └── podman-5.4.2.tbz2
└── ...
```

`packages/Packages` (the index) is `.gitignore`-d on purpose: it is
regenerated from the tree by `emaint binhost --fix` every time the OCI image
builds. Never commit an index — only commit `.tbz2` files and their
`Manifest`/`metadata` siblings if a package ships any.

See `../docs/adding-packages.md` for the full "add or update a package" walkthrough.
# Binhost overlay (packages/)

This directory is an **optional fast path** for the binhost: drop prebuilt
`.tbz2` binaries here so the factory doesn't have to compile them. It is *not*
the full cache — the factory builds `config/gap-build.txt` itself and stages
these files *into* that overlay before regenerating the index.

```
packages/
├── sys-kernel/
│   └── gentoo-kernel-bin-6.14_rc4_p4.tbz2
├── app-containers/
│   └── podman-5.4.2.tbz2
└── ...
```

Preserve the category layout the official binhost uses so the staged paths stay
recognizable.

`packages/Packages` (the index) is `.gitignore`-d on purpose: it is regenerated
from the tree by `emaint binhost --fix` every time the OCI image builds. Never
commit an index — only commit `.tbz2` files.

See `../docs/adding-packages.md` for the full "add or update a package" walkthrough.
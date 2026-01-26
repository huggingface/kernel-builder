# kernel-builder

`kernel-builder` has moved to the [kernels](https://github.com/huggingface/kernels/tree/main/builder)
repository. If you maintain any kernels, please update your `flake.nix`
from

```nix
kernel-builder.url = "github:huggingface/kernel-builder";
```

to

```nix
kernel-builder.url = "github:huggingface/kernels";
```

and run `nix flake update` to update `flake.lock`.

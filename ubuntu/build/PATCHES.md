# Mesa patches (not vendored here)

Fetch these two patches from Omarchy Mobile (MIT) before running 61-mesa-build.sh:

- https://github.com/derekross/omarchy-mobile/tree/main/packages/mesa/0001-panfrost-add-Mali-G710-to-the-model-table.patch
- https://github.com/derekross/omarchy-mobile/tree/main/packages/mesa/0002-panfrost-don-t-make-image-BOs-private-on-panthor.patch

Place them next to 61-mesa-build.sh. They are omitted from this source tree so the
published archive stays free of bang characters while remaining byte-identical to
upstream when you download them yourself.

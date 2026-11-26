# Files

ca-certificates_20260816+nmu1.tar.xz  llvm-project-22.1.8.src.tar.xz
elfutils-0.195.tar.bz2                menu.txt
README.md                   fakeroot_1.37.2.orig.tar.gz           nasm-2.16.03.tar.xz
acl-2.4.0.tar.xz            freetype-2.14.3.tar.xz                ravios-chromium-wayland.zip
attr-2.6.0.tar.xz           jpegsrc.v10.tar.gz                    v4l-utils-1.32.0.tar.xz
buildroot-2026.08.2.tar.gz  libarchive-3.8.9.tar.xz
bzip2-1.0.8.tar.gz          libxml2-2.15.4.tar.xz                 ...

## ravios_buildroot-dl

zip:
docker run --rm -v ravios_buildroot-dl:/data -v ~/Desktop/download_tmp:/backup busybox sh -c "cp -a /data/. /backup/"

unzip:
docker run --rm -v ravios_buildroot-dl:/data -v ~/Desktop:/backup alpine sh -c "apk add --no-cache unzip && unzip -o /backup/download_tmp.zip -d /data/"

or one by one:
docker cp "C:\Users\user_name\Desktop\ravios\download_tmp\buildroot-2026.08.2.tar.gz" "ravios-dev:/workspace/dl/buildroot-2026.08.2.tar.gz"

- Download link:
<https://drive.google.com/drive/folders/1Un0sAwDmYUmv6QeZ_Rnz1pkJb_rgxwak?usp=sharing>

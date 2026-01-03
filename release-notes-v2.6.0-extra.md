SHA256 do asset:

87e3dfd55cacd7a09cd6d1b0be5af024dc011b86e16c3fbfa3ceceb5966acfa4  oci-expand-disk.sh

Instruções de download e verificação:

curl -fsSLO https://github.com/beniciont/oci-linux-disk-expander/releases/download/v2.6.0/oci-expand-disk.sh

echo "87e3dfd55cacd7a09cd6d1b0be5af024dc011b86e16c3fbfa3ceceb5966acfa4  oci-expand-disk.sh" | sha256sum -c -

chmod +x oci-expand-disk.sh

# Opcional: assinatura GPG (se disponível futuramente)
# curl -fsSLO https://github.com/beniciont/oci-linux-disk-expander/releases/download/v2.6.0/oci-expand-disk.sh.sig
# gpg --keyserver keyserver.ubuntu.com --recv-keys SEU_KEYID
# gpg --verify oci-expand-disk.sh.sig oci-expand-disk.sh

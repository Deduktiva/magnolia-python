// Sanity-check the staged OpenSSL install before handing it to CPython's
// configure (Unix) or to MagPython.vcxproj (Windows). Catches a misconfigured
// no-* set or a missing soname here, with a clear error, instead of surfacing
// 50 layers deep as a silent
//   "checking whether OpenSSL provides required ssl module APIs... no"
//
// Exercises the same APIs CPython's _ssl.c and _hashopenssl.c reach for
// during configure/link: SSL_new/SSL_CTX, EVP digest, HMAC. Print the
// version we actually loaded so a sonume mismatch (loading an older system
// libssl by accident) would show up in the build log.

#include <stdio.h>
#include <openssl/ssl.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/opensslv.h>

int main(void) {
    SSL_CTX *ctx = SSL_CTX_new(TLS_method());
    if (!ctx) {
        fprintf(stderr, "SSL_CTX_new failed\n");
        return 1;
    }
    SSL_CTX_free(ctx);

    EVP_MD_CTX *md = EVP_MD_CTX_new();
    if (!md) {
        fprintf(stderr, "EVP_MD_CTX_new failed\n");
        return 2;
    }
    EVP_MD_CTX_free(md);

    HMAC_CTX *h = HMAC_CTX_new();
    if (!h) {
        fprintf(stderr, "HMAC_CTX_new failed\n");
        return 3;
    }
    HMAC_CTX_free(h);

    printf("openssl-verify: %s OK\n", OPENSSL_VERSION_TEXT);
    return 0;
}

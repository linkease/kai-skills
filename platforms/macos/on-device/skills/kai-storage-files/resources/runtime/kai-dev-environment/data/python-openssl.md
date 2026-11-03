# iStoreOS bundled Python OpenSSL

Observed on the frozen iStoreOS24.10.1 image, Python3.13.7 musl installs after
successful GitHub artifact attestation, then SSLContext creation fails with
`CONF: UNKNOWN_MODULE_NAME`. Firmware openssl.cnf has config_diagnostics=1 and
an ENGINE initializer; its Python library and firmware OpenSSL are independent.
No curl/libcurl/libssl upgrade is needed to investigate this mismatch.

The adapter recognizes only the immutable firmware default SHA in
python-openssl.lock.json. It accepts only absent/comment-only engine/provider
extension files and the exact SHA-locked factory legacy.cnf declaration. The
locked default never references legacy_sect; enabling it through providers.cnf
or any other extension is rejected. The adapter creates an exact SHA-checked copy under the runtime HOME, and
comments the empty ENGINE initialization line. Every other byte, including
providers, diagnostic enforcement and absolute include paths, remains unchanged.
An explicit OPENSSL_CONF is preserved; custom policy is not silently translated.
Modified compatibility copies cause a conflict. Only Python task descendants
inherit the copy. Direct unrelated shells and firmware files are unchanged.

OpenSSL documents per-process OPENSSL_CONF selection, module initialization,
ENGINE configuration and config_diagnostics in its [official configuration
manual](https://docs.openssl.org/3.5/man5/config/). This adapter does not set an
empty configuration, ignore configuration errors, disable certificate/hostname
checks or replace CA roots.

Acceptance requires SDK module checks and real loopback TLS: a fresh untrusted
self-signed certificate fails, an explicitly trusted correct hostname succeeds,
and a trusted certificate with the wrong hostname fails. System curl/library/
opkg hashes and the original openssl.cnf must remain unchanged. A fixture passing
alone is not native SDK acceptance; see the milestone result.

CA directories load lazily: an empty get_ca_certs() list before a handshake
does not prove missing roots. The module check reports default verify paths and
loaded count as diagnostics; trust behavior is a separate gate. The TLS probe
also accepts --capath DIRECTORY to exercise a hashed certificate directory and
--system-trust-host HOST for an explicit, certificate-verified HTTPS handshake
with the unchanged system defaults. Native acceptance uses pypi.org; offline
contracts use loopback only. Neither mode turns verification off or replaces
the platform CA store. See Python's [get_ca_certs documentation](https://docs.python.org/3/library/ssl.html#ssl.SSLContext.get_ca_certs).

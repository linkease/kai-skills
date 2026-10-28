// A standalone external HTTP service fixture, not a KSpeeder implementation.
// It makes health succeed and capability negotiation fail before tool execution.
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"math/big"
	"net/http"
	"os"
	"time"
)

func main() {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	cert := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "localhost"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), DNSNames: []string{"localhost"},
		KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	der, err := x509.CreateCertificate(rand.Reader, cert, cert, &key.PublicKey, key)
	if err != nil {
		panic(err)
	}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(os.Stdout).Encode(map[string]string{"method": r.Method, "path": r.URL.Path})
		if r.URL.Path == "/direct-content" {
			w.Header().Set("Content-Type", "application/octet-stream")
			w.Write([]byte("kai native direct origin fixture\n"))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/api/v1/capabilities" {
			json.NewEncoder(w).Encode(map[string]any{"schema_version": 1, "service": map[string]string{"version": "fixture"}, "capabilities": []string{}})
			return
		}
		w.Write([]byte("{}"))
	})
	go func() { panic(http.ListenAndServe("127.0.0.1:5003", handler)) }()
	server := &http.Server{Addr: "127.0.0.1:5443", Handler: handler, TLSConfig: &tls.Config{Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}}}
	panic(server.ListenAndServeTLS("", ""))
}

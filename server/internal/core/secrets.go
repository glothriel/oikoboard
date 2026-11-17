package core

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
)

// ErrNoSecretKey: OIKO_SECRET_KEY is not set, so secrets (provider refresh
// tokens) cannot be stored.
var ErrNoSecretKey = errors.New("OIKO_SECRET_KEY is not set")

// Sealer encrypts secrets at rest (AES-256-GCM). A nil *Sealer refuses to
// seal or open anything.
type Sealer struct{ aead cipher.AEAD }

// NewSealer takes a 32-byte key as base64 or hex; empty key → nil Sealer.
func NewSealer(key string) (*Sealer, error) {
	if key == "" {
		return nil, nil
	}
	raw, err := base64.StdEncoding.DecodeString(key)
	if err != nil || len(raw) != 32 {
		raw, err = hex.DecodeString(key)
	}
	if err != nil || len(raw) != 32 {
		return nil, fmt.Errorf("secret key must be 32 bytes, base64 or hex encoded")
	}
	block, err := aes.NewCipher(raw)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &Sealer{aead}, nil
}

func (s *Sealer) Seal(plain []byte) (string, error) {
	if s == nil {
		return "", ErrNoSecretKey
	}
	nonce := make([]byte, s.aead.NonceSize())
	_, _ = rand.Read(nonce)
	return base64.RawStdEncoding.EncodeToString(s.aead.Seal(nonce, nonce, plain, nil)), nil
}

func (s *Sealer) Open(sealed string) ([]byte, error) {
	if s == nil {
		return nil, ErrNoSecretKey
	}
	raw, err := base64.RawStdEncoding.DecodeString(sealed)
	if err != nil || len(raw) < s.aead.NonceSize() {
		return nil, errors.New("malformed secret")
	}
	n := s.aead.NonceSize()
	return s.aead.Open(nil, raw[:n], raw[n:], nil)
}

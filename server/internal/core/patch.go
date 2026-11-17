package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// Patch to body PATCH-a: odróżnia brak pola od jawnego null.
type Patch map[string]json.RawMessage

func BindPatch(c *gin.Context) (Patch, bool) {
	var p Patch
	if !Bind(c, &p) {
		return nil, false
	}
	return p, true
}

// Apply przepisuje dozwolone pola do mapy kolumn dla gorm.Updates.
// fields: nazwa pola JSON → wskaźnik do zmiennej docelowej (typ wyznacza
// dekodowanie; null zapisuje NULL).
func (p Patch) Apply(fields map[string]any) (map[string]any, error) {
	out := map[string]any{}
	for k := range p {
		if _, ok := fields[k]; !ok {
			return nil, fmt.Errorf("pole %q nie może być zmieniane", k)
		}
	}
	for k, dst := range fields {
		raw, ok := p[k]
		if !ok {
			continue
		}
		if string(raw) == "null" {
			out[k] = nil
			continue
		}
		if err := json.Unmarshal(raw, dst); err != nil {
			return nil, fmt.Errorf("pole %q: %w", k, err)
		}
		out[k] = derefAny(dst)
	}
	return out, nil
}

func derefAny(p any) any { return reflect.ValueOf(p).Elem().Interface() }

var ErrIDConflict = errors.New("id zajęte")

// CreateIdempotent wstawia wiersz o id nadanym przez klienta. Ponowienie
// tego samego POST-a (retry) nie tworzy duplikatu — zwraca istniejący wiersz.
func CreateIdempotent(tx *gorm.DB, row any, householdID, id any) error {
	res := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(row)
	if res.Error != nil {
		return res.Error
	}
	err := tx.Where("household_id = ? AND id = ?", householdID, id).First(row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrIDConflict
	}
	return err
}

package core

import (
	"encoding/json"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

// Change to wiersz z tabeli changes.
type Change struct {
	HouseholdID uuid.UUID  `json:"household_id"`
	Seq         int64      `json:"seq"`
	Entity      string     `json:"entity"`
	EntityID    uuid.UUID  `json:"entity_id"`
	Op          string     `json:"op"`
	Before      RawJSON    `json:"before"`
	After       RawJSON    `json:"after"`
	ActorID     *uuid.UUID `json:"actor_id"`
	MutationID  *uuid.UUID `json:"mutation_id"`
	CreatedAt   time.Time  `json:"created_at"`
}

// Entities: nazwa encji (tabeli) → wiersze.
type Entities map[string]any

// View to nazwany zbiór encji z parametrami — to, co pokazuje jeden ekran.
// Klient subskrybuje (view, params); dostaje snapshot, a potem tylko te
// zmiany, które dotyczą encji należących (albo należących wcześniej) do widoku.
type View interface {
	Name() string
	// ParseParams waliduje parametry subskrypcji.
	ParseParams(raw json.RawMessage) (any, error)
	// Snapshot zwraca aktualny stan widoku. tx to transakcja REPEATABLE READ,
	// ograniczenie do gospodarstwa robi widok (warunek household_id).
	Snapshot(tx *gorm.DB, hh uuid.UUID, params any) (Entities, error)
	// Matches mówi, czy wiersz encji (z changes.before/after) należy do widoku.
	Matches(params any, entity string, row json.RawMessage) bool
}

// Module to funkcja aplikacji (todo, kalendarz, waga…).
type Module interface {
	Name() string
	Routes(r *gin.RouterGroup)
	Views() []View
}

// RowProjector is optionally implemented by a View whose rows must be
// transformed (e.g. sanitized) before they are sent to clients in live changes.
type RowProjector interface {
	Project(entity string, row json.RawMessage) json.RawMessage
}

type Action int

const (
	Skip Action = iota
	Upsert
	Remove
)

// Classify decyduje, co subskrypcja widoku ma dostać dla danej zmiany.
func Classify(v View, params any, ch *Change) Action {
	was := ch.Before != nil && v.Matches(params, ch.Entity, json.RawMessage(ch.Before))
	is := ch.After != nil && v.Matches(params, ch.Entity, json.RawMessage(ch.After))
	switch {
	case is:
		return Upsert
	case was:
		return Remove
	default:
		return Skip
	}
}

// Views to rejestr widoków wszystkich modułów.
type Views map[string]View

func CollectViews(mods []Module) Views {
	out := Views{}
	for _, m := range mods {
		for _, v := range m.Views() {
			out[v.Name()] = v
		}
	}
	return out
}

// DecodeRow to pomocnik dla Matches.
func DecodeRow[T any](row json.RawMessage) (T, bool) {
	var v T
	if err := json.Unmarshal(row, &v); err != nil {
		return v, false
	}
	return v, true
}

// NoParams dla widoków bez parametrów.
func NoParams(json.RawMessage) (any, error) { return struct{}{}, nil }

// Package seed: przykładowa rodzina do developmentu.
package seed

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"oikoboard/server/internal/core"
	"oikoboard/server/internal/modules/calendar"
	"oikoboard/server/internal/modules/todo"
)

// Run tworzy jedną przykładową rodzinę, jeśli w bazie nie ma żadnej.
// Zwraca false, jeśli nic nie zrobił.
func Run(ctx context.Context, db *gorm.DB) (bool, error) {
	var n int64
	if err := db.WithContext(ctx).Model(&core.Household{}).Count(&n).Error; err != nil {
		return false, err
	}
	if n > 0 {
		return false, nil
	}
	return true, Family(ctx, db, DefaultFamily)
}

const DefaultFamily = "Nasza rodzina"

// LinkEmail: członek rodziny czeka na konto z tym e-mailem — zostanie do
// niego przypięty przy pierwszym logowaniu (zweryfikowanym adresem).
func LinkEmail(ctx context.Context, db *gorm.DB, household, member, email string) error {
	res := db.WithContext(ctx).Exec(`
		UPDATE members m SET invite_email = ?
		FROM households h
		WHERE h.id = m.household_id AND h.name = ? AND m.name = ? AND m.user_id IS NULL`,
		strings.ToLower(strings.TrimSpace(email)), household, member)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected != 1 {
		return fmt.Errorf("nie ma członka %q bez konta w rodzinie %q (albo jest kilka)", member, household)
	}
	return nil
}

// Family tworzy rodzinę z członkami, listami i wydarzeniami (względem dziś).
func Family(ctx context.Context, db *gorm.DB, name string) error {
	return db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		hh := core.Household{Name: name}
		if err := tx.Create(&hh).Error; err != nil {
			return err
		}
		people := []struct {
			name  string
			color int64
		}{
			{"Mama", 0xFFE57373}, {"Tata", 0xFF5C6BC0}, {"Ola", 0xFFAB47BC}, {"Kuba", 0xFF26A69A},
		}
		ids := map[string]uuid.UUID{}
		for _, p := range people {
			m := core.Member{HouseholdID: hh.ID, Name: p.name, Color: p.color}
			if err := tx.Create(&m).Error; err != nil {
				return err
			}
			ids[p.name] = m.ID
		}
		ptr := func(s string) *uuid.UUID {
			if s == "" {
				return nil
			}
			id := ids[s]
			return &id
		}

		now := time.Now()
		day := func(d, h, min int) time.Time {
			return time.Date(now.Year(), now.Month(), now.Day()+d, h, min, 0, 0, time.Local)
		}

		type item struct {
			title, who string
			done       bool
			dueIn      int // 0 = brak
		}
		addList := func(name string, color int64, items []item) error {
			l := todo.List{ID: uuid.New(), HouseholdID: hh.ID, Name: name, Color: color}
			if err := tx.Create(&l).Error; err != nil {
				return err
			}
			for _, it := range items {
				row := todo.Item{ID: uuid.New(), HouseholdID: hh.ID, ListID: l.ID,
					Title: it.title, Done: it.done, AssigneeID: ptr(it.who)}
				if it.done {
					row.DoneAt = &now
				}
				if it.dueIn != 0 {
					due := core.DateOf(day(it.dueIn, 0, 0))
					row.Due = &due
				}
				if err := tx.Create(&row).Error; err != nil {
					return err
				}
			}
			return nil
		}
		if err := addList("Zakupy", 0xFF26A69A, []item{
			{title: "Mleko"}, {title: "Chleb"}, {title: "Jajka (10 szt.)"},
			{title: "Pomidory", done: true}, {title: "Płyn do naczyń", who: "Tata"},
		}); err != nil {
			return err
		}
		if err := addList("Dom", 0xFF5C6BC0, []item{
			{title: "Wymienić żarówkę w łazience", who: "Tata"},
			{title: "Odkurzyć pokój", who: "Kuba"},
			{title: "Zapłacić za prąd", who: "Mama", dueIn: 2},
			{title: "Podlać kwiatki", who: "Ola", dueIn: -1},
			{title: "Wynieść śmieci", who: "Kuba", done: true},
		}); err != nil {
			return err
		}
		if err := addList("Wakacje", 0xFFFFA726, []item{
			{title: "Zarezerwować nocleg", who: "Mama"},
			{title: "Paszport dla Oli", dueIn: 14},
			{title: "Kupić krem z filtrem"},
		}); err != nil {
			return err
		}

		all := []string{"Mama", "Tata", "Ola", "Kuba"}
		ev := func(title string, start, end time.Time, allDay bool, who ...string) calendar.RemoteEvent {
			var mids []uuid.UUID
			for _, w := range who {
				mids = append(mids, ids[w])
			}
			if allDay {
				start = time.Date(start.Year(), start.Month(), start.Day(), 0, 0, 0, 0, time.UTC)
				end = time.Date(end.Year(), end.Month(), end.Day(), 0, 0, 0, 0, time.UTC)
			}
			return calendar.RemoteEvent{Title: title, Start: start, End: end, AllDay: allDay,
				TimeZone: "Europe/Warsaw", MemberIDs: mids, Status: "confirmed"}
		}
		weekly := func(e calendar.RemoteEvent, rule string) calendar.RemoteEvent {
			e.Recurrence = []string{rule}
			return e
		}
		return calendar.SeedMock(tx, hh.ID, map[string][]calendar.RemoteEvent{
			"family": {
				ev("Przegląd auta", day(-5, 9, 0), day(-5, 10, 0), false, "Tata"),
				weekly(ev("Basen", day(-7, 17, 0), day(-7, 18, 0), false, "Ola"), "RRULE:FREQ=WEEKLY;COUNT=12"),
				ev("Dentysta — Kuba", day(1, 16, 30), day(1, 17, 30), false, "Mama", "Kuba"),
				ev("Kolacja u sąsiadów", day(1, 19, 0), day(1, 22, 0), false, "Mama", "Tata"),
				ev("Urodziny babci", day(3, 0, 0), day(4, 0, 0), true, all...),
				ev("Piłka nożna", day(5, 10, 0), day(5, 12, 0), false, "Kuba", "Tata"),
				ev("Wyjazd w góry", day(9, 0, 0), day(12, 0, 0), true, all...),
			},
			"school": {
				weekly(ev("Odwieźć Kubę do szkoły", day(-14, 7, 30), day(-14, 8, 0), false, "Tata"),
					"RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"),
				ev("Zebranie w szkole", day(2, 18, 0), day(2, 19, 30), false, "Mama"),
			},
			"holidays": {
				ev("Dzień wolny", day(20, 0, 0), day(21, 0, 0), true),
			},
		})
	})
}

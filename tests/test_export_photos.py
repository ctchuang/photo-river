"""Tests for scripts/export_photos.py. They use stand-in photo objects, never the Photos library.

    uv run python -m unittest discover tests
"""
import datetime as dt
import importlib.util
import pathlib
import tempfile
import unittest
from types import SimpleNamespace

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "export_photos.py"
spec = importlib.util.spec_from_file_location("export_photos", SCRIPT)
export_photos = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export_photos)

TAIPEI = dt.timezone(dt.timedelta(hours=8))


def photo(uuid="A", date=dt.datetime(2010, 9, 19, 11, 14, tzinfo=TAIPEI), hidden=False, location=(41.9, 12.47), **extra):
    """A stand-in for osxphotos.PhotoInfo with only the attributes the exporter reads."""
    fields = dict(uuid=uuid, date=date, hidden=hidden, location=location,
                  persons=[], labels=[], score=None, exif_info=None)
    fields.update(extra)
    return SimpleNamespace(**fields)


class SkipReasonTests(unittest.TestCase):
    def test_keeps_an_ordinary_photo(self):
        self.assertIsNone(export_photos.skip_reason(photo()))

    def test_skips_hidden_photos(self):
        self.assertEqual(export_photos.skip_reason(photo(hidden=True)), "hidden")

    def test_skips_photos_without_a_date(self):
        self.assertEqual(export_photos.skip_reason(photo(date=None)), "no date")

    def test_skips_the_1980_placeholder_date_in_any_time_zone(self):
        for tz in (TAIPEI, dt.timezone.utc, dt.timezone(dt.timedelta(hours=-7))):
            self.assertEqual(export_photos.skip_reason(photo(date=dt.datetime(1980, 1, 1, tzinfo=tz))), "placeholder date")

    def test_keeps_other_1980_dates(self):
        self.assertIsNone(export_photos.skip_reason(photo(date=dt.datetime(1980, 1, 1, 9, 30, tzinfo=TAIPEI))))
        self.assertIsNone(export_photos.skip_reason(photo(date=dt.datetime(1980, 6, 1, tzinfo=TAIPEI))))

    def test_hidden_wins_over_other_reasons(self):
        self.assertEqual(export_photos.skip_reason(photo(hidden=True, date=None)), "hidden")


class SelectRowsTests(unittest.TestCase):
    def test_hidden_photos_never_reach_the_output(self):
        photos = [
            photo("old", date=dt.datetime(2005, 1, 1, tzinfo=TAIPEI)),
            photo("secret", hidden=True),
            photo("new", date=dt.datetime(2020, 1, 1, tzinfo=TAIPEI)),
            photo("placeholder", date=dt.datetime(1980, 1, 1, tzinfo=TAIPEI)),
        ]
        rows, skipped = export_photos.select_rows(photos, full=False)
        self.assertEqual([r["photo"].uuid for r in rows], ["old", "new"])
        self.assertEqual(skipped, {"hidden": 1, "placeholder date": 1})

        out = export_photos.build_output(rows, full=False, movies=False, thumbs=True, today=dt.date(2026, 10, 24))
        self.assertEqual(out["id"], ["old", "new"])
        self.assertEqual(out["meta"]["count"], 2)

    def test_rows_are_sorted_by_time(self):
        photos = [photo(str(y), date=dt.datetime(y, 1, 1, tzinfo=TAIPEI)) for y in (2019, 2003, 2011)]
        rows, _ = export_photos.select_rows(photos, full=False)
        self.assertEqual([r["photo"].uuid for r in rows], ["2003", "2011", "2019"])
        self.assertEqual([r["t"] for r in rows], sorted(r["t"] for r in rows))

    def test_photos_without_location_get_null_coordinates(self):
        rows, _ = export_photos.select_rows([photo(location=(None, None)), photo("B", location=None)], full=False)
        self.assertEqual([(r["lat"], r["lng"]) for r in rows], [(None, None), (None, None)])


class BuildOutputTests(unittest.TestCase):
    def test_minimal_export_has_only_time_and_place_columns(self):
        rows, _ = export_photos.select_rows([photo()], full=False)
        out = export_photos.build_output(rows, full=False, movies=False, thumbs=False, today=dt.date(2026, 10, 24))
        self.assertEqual(set(out), {"meta", "t", "lat", "lng", "hour"})
        self.assertNotIn("thumbs", out["meta"])
        self.assertEqual(out["hour"], [11.23])
        self.assertEqual((out["lat"], out["lng"]), ([41.9], [12.47]))

    def test_full_export_drops_unknown_people(self):
        p = photo(persons=["Alice", "_UNKNOWN_", ""], labels=["Fountain"], score=SimpleNamespace(overall=0.71234),
                  exif_info=SimpleNamespace(camera_model="Canon EOS 5D"))
        rows, _ = export_photos.select_rows([p], full=True)
        out = export_photos.build_output(rows, full=True, movies=False, thumbs=False, today=dt.date(2026, 10, 24))
        self.assertEqual(out["persons"], [["Alice"]])
        self.assertEqual(out["labels"], [["Fountain"]])
        self.assertEqual(out["score"], [0.712])
        self.assertEqual(out["camera"], ["Canon EOS 5D"])


class PruneThumbsTests(unittest.TestCase):
    def test_removes_thumbnails_of_photos_no_longer_exported(self):
        with tempfile.TemporaryDirectory() as d:
            thumb_dir = pathlib.Path(d)
            for name in ("visible", "now-hidden", "deleted"):
                (thumb_dir / f"{name}.jpg").write_bytes(b"jpeg")
            (thumb_dir / "notes.txt").write_text("not a thumbnail")

            rows, _ = export_photos.select_rows([photo("visible"), photo("now-hidden", hidden=True)], full=False)
            removed = export_photos.prune_thumbs(rows, thumb_dir)

            self.assertEqual(removed, 2)
            self.assertEqual(sorted(f.name for f in thumb_dir.iterdir()), ["notes.txt", "visible.jpg"])


if __name__ == "__main__":
    unittest.main()

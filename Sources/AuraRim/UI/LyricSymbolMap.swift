import Foundation
import NaturalLanguage

/// Maps lyric words to SF Symbols for the "Visual" style (Verci pairs ~770 words
/// with icons). We lemmatize each word with NaturalLanguage so inflections
/// ("running", "ran") resolve to the base form ("run") before lookup. Original
/// curated mapping — no assets copied.
enum LyricSymbolMap {
    /// Returns an SF Symbol name for a word, or nil if nothing fits.
    static func symbol(for rawWord: String) -> String? {
        let cleaned = rawWord.lowercased().filter { $0.isLetter }
        guard cleaned.count > 1 else { return nil }
        if let direct = table[cleaned] { return direct }
        let base = lemma(of: cleaned)
        return table[base]
    }

    private static func lemma(of word: String) -> String {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        let range = word.startIndex..<word.endIndex
        if let tag = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0 {
            let l = tag.rawValue.lowercased()
            if !l.isEmpty { return l }
        }
        _ = range
        return word
    }

    /// Curated word → SF Symbol table (base/lemma forms).
    private static let table: [String: String] = [
        // Emotion / people
        "love": "heart.fill", "heart": "heart.fill", "hate": "heart.slash.fill",
        "cry": "drop.fill", "tear": "drop.fill", "smile": "face.smiling",
        "happy": "face.smiling", "sad": "cloud.rain.fill", "soul": "sparkles",
        "friend": "person.2.fill", "people": "person.3.fill", "baby": "figure.child",
        "girl": "person.fill", "boy": "person.fill", "man": "person.fill",
        "woman": "person.fill", "king": "crown.fill", "queen": "crown.fill",
        "angel": "sparkles", "devil": "flame.fill", "god": "sun.max.fill",
        "enemy": "person.fill.xmark", "family": "house.fill",
        // Body
        "eye": "eye.fill", "hand": "hand.raised.fill", "head": "brain.head.profile",
        "mind": "brain", "brain": "brain", "face": "face.smiling", "voice": "waveform",
        "blood": "drop.fill", "bone": "figure.walk", "skin": "hand.raised.fill",
        // Nature / sky
        "sun": "sun.max.fill", "moon": "moon.fill", "star": "star.fill",
        "sky": "cloud.fill", "cloud": "cloud.fill", "rain": "cloud.rain.fill",
        "storm": "cloud.bolt.rain.fill", "thunder": "cloud.bolt.fill",
        "lightning": "bolt.fill", "wind": "wind", "snow": "snowflake",
        "fire": "flame.fill", "flame": "flame.fill", "burn": "flame.fill",
        "ice": "snowflake", "cold": "thermometer.snowflake", "hot": "thermometer.sun.fill",
        "water": "drop.fill", "ocean": "water.waves", "sea": "water.waves",
        "wave": "water.waves", "river": "water.waves", "mountain": "mountain.2.fill",
        "tree": "tree.fill", "flower": "camera.macro", "rose": "camera.macro",
        "earth": "globe.americas.fill", "world": "globe", "leaf": "leaf.fill",
        "light": "light.max", "dark": "moon.fill", "shadow": "moon.fill",
        "night": "moon.stars.fill", "day": "sun.max.fill", "morning": "sunrise.fill",
        "sunset": "sunset.fill", "gold": "sparkles", "diamond": "diamond.fill",
        // Motion / actions
        "run": "figure.run", "walk": "figure.walk", "dance": "figure.dance",
        "fall": "arrow.down", "rise": "arrow.up", "fly": "airplane",
        "drive": "car.fill", "ride": "car.fill", "move": "arrow.up.arrow.down",
        "stop": "stop.fill", "go": "play.fill", "jump": "figure.jumprope",
        "fight": "figure.boxing", "win": "trophy.fill", "lose": "flag.slash",
        "sing": "music.mic", "play": "play.fill", "sleep": "moon.zzz.fill",
        "dream": "moon.stars.fill", "wake": "sunrise.fill", "die": "xmark",
        "live": "heart.fill", "breathe": "lungs.fill", "look": "eye.fill",
        "see": "eye.fill", "hear": "ear.fill", "listen": "ear.fill",
        "talk": "bubble.left.fill", "speak": "bubble.left.fill", "call": "phone.fill",
        "wait": "hourglass", "hold": "hand.raised.fill", "give": "gift.fill",
        "take": "hand.tap.fill", "shine": "sparkles", "glow": "light.max",
        "shoot": "scope", "shooter": "scope",
        // Things
        "money": "dollarsign.circle.fill", "cash": "banknote.fill", "car": "car.fill",
        "phone": "phone.fill", "clock": "clock.fill", "time": "clock.fill",
        "road": "road.lanes", "home": "house.fill", "house": "house.fill",
        "door": "door.left.hand.open", "key": "key.fill", "gun": "scope",
        "crown": "crown.fill", "ring": "circle.circle", "bottle": "waterbottle.fill",
        "letter": "envelope.fill", "book": "book.fill", "music": "music.note",
        "song": "music.note", "beat": "waveform.path", "drum": "waveform.path",
        "guitar": "guitars.fill", "party": "party.popper.fill", "gift": "gift.fill",
        "camera": "camera.fill", "map": "map.fill", "gamespot": "gamecontroller.fill",
        // Abstract
        "life": "heart.fill", "death": "xmark.circle", "hope": "sparkles",
        "faith": "hands.and.sparkles.fill", "truth": "checkmark.seal.fill",
        "lie": "xmark.seal.fill", "pain": "bolt.heart.fill", "peace": "peacesign",
        "power": "bolt.fill", "energy": "bolt.fill", "trust": "hand.raised.fill",
        "fear": "exclamationmark.triangle.fill", "danger": "exclamationmark.triangle.fill",
        "crazy": "tornado", "wild": "flame.fill", "high": "arrow.up.circle.fill",
        "low": "arrow.down.circle.fill", "up": "arrow.up", "down": "arrow.down",
        "forever": "infinity", "never": "nosign", "alone": "person.fill",
        "together": "person.2.fill", "again": "arrow.clockwise", "new": "sparkles",
        "young": "leaf.fill", "old": "hourglass", "real": "checkmark.seal.fill",
        "fake": "xmark.seal.fill", "lost": "questionmark.circle.fill", "found": "checkmark.circle.fill",
        // More common lyric vocabulary (unique keys only)
        "kiss": "mouth.fill", "lip": "mouth.fill", "smoke": "smoke.fill", "cigarette": "smoke.fill",
        "drink": "wineglass.fill", "wine": "wineglass.fill", "cup": "cup.and.saucer.fill",
        "throne": "crown.fill", "jewel": "diamond.fill", "chain": "link",
        "flash": "camera.aperture", "spark": "sparkle", "silver": "sparkles", "glitter": "sparkles",
        "heaven": "cloud.sun.fill", "hell": "flame.fill", "pray": "hands.and.sparkles.fill",
        "church": "building.columns.fill", "bell": "bell.fill",
        "war": "shield.fill", "battle": "shield.lefthalf.filled", "soldier": "figure.walk",
        "ghost": "figure.wave", "monster": "pawprint.fill",
        "wing": "airplane", "bird": "bird.fill", "dog": "dog.fill", "cat": "cat.fill",
        "snake": "pawprint.fill", "lion": "pawprint.fill", "wolf": "pawprint.fill",
        "text": "message.fill", "message": "message.fill",
        "screen": "rectangle.fill", "tv": "tv.fill", "movie": "film.fill",
        "photo": "photo.fill", "selfie": "camera.fill", "video": "video.fill",
        "plane": "airplane", "flight": "airplane", "train": "tram.fill", "boat": "sailboat.fill",
        "wheel": "steeringwheel", "engine": "engine.combustion.fill",
        "street": "road.lanes", "city": "building.2.fill", "town": "building.2.fill",
        "block": "square.grid.3x3.fill", "hood": "house.fill", "bed": "bed.double.fill",
        "bank": "banknote.fill", "dollar": "dollarsign.circle.fill", "rich": "dollarsign.circle.fill",
        "broke": "creditcard.trianglebadge.exclamationmark", "work": "hammer.fill", "job": "briefcase.fill",
        "grind": "gearshape.fill", "hustle": "bolt.fill", "boss": "person.badge.key.fill",
        "hour": "clock.fill", "minute": "clock.fill", "week": "calendar", "month": "calendar",
        "year": "calendar", "summer": "sun.max.fill", "winter": "snowflake",
        "laugh": "face.smiling.inverse", "joy": "face.smiling",
        "hurt": "bandage.fill", "broken": "heart.slash.fill", "heal": "cross.case.fill",
        "sick": "cross.case.fill", "medicine": "pills.fill", "pill": "pills.fill",
        "chase": "figure.run", "escape": "figure.run", "free": "bird.fill",
        "cage": "lock.fill", "lock": "lock.fill", "trap": "lock.fill",
        "prince": "crown.fill", "flood": "water.waves", "drown": "water.waves",
        "touch": "hand.tap.fill", "feel": "hand.tap.fill",
        "eyes": "eye.fill", "tears": "drop.fill",
        "knife": "scissors", "loss": "flag.slash", "game": "gamecontroller.fill",
        "score": "sportscourt.fill"
    ]
}

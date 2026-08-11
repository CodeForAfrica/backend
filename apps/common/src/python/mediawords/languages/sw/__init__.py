from mediawords.languages import SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn


class SwahiliLanguage(SpaceSeparatedWordsMixIn, SentenceSplitterMixIn, PyStemmerMixIn, StopWordsFromFileMixIn):
    """Swahili language support module."""

    @staticmethod
    def language_code() -> str:
        return "sw"

    @staticmethod
    def sample_sentence() -> str:
        return "Huduma za afya ni muhimu sana kwa wananchi wote."

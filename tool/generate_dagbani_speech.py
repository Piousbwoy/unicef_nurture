"""Generate the on-device speech banks for CareBridge.

Downloads Meta's MMS text-to-speech checkpoints (VITS) via open community
mirrors of the access-gated `facebook/mms-tts-*` repos and synthesizes one
WAV per script in `lib/core/i18n/speech_bank.dart`, keyed by the exact
`VoiceRequest.id` values VoiceService queries:

  - audio topics:  `child_danger_signs`, `feeding`, ...
  - triage questions: `q_newborn.feed`, `q_mother.fits`, ...
  - level messages: `level_urgent`, `level_priority`, ...
  - caregiver verdicts: `caregiver_verdict_urgent`, ...
  - nurse-words frame: `nurse_intro`, `nurse_unsure`, `nurse_close`
  - standalone: `setup_preview_<Language>`, `voice_test_<Language>`

Three banks today, one folder each under `assets/audio/`:

  dagbani_mms  — IanKobby/mms-tts-dag-ghana   (upstream facebook/mms-tts-dag)
  hausa_mms    — laztopaz/mms-tts-hau-custom  (upstream facebook/mms-tts-hau)
  twi_mms      — IanKobby/mms-tts-twi-ghana   (upstream facebook/mms-tts-twi)

The phrase text mirrors `lib/core/i18n/speech_bank.dart` (the clip map) and
`lib/core/i18n/dagbani_strings.dart` (the Dagbani wording) — the Dart-side
asset coverage test (`test/speech_bank_test.dart`) fails if a clip id and a
bank file ever drift apart.

Output lands in `assets/audio/<bank>/<id>.wav` (16 kHz mono PCM16) plus a
manifest.json. The generated clips are **synthesized drafts of draft
translations** — the UI labels them as such; they are never presented as
studio recordings.

Usage:  python tool\\generate_dagbani_speech.py [bank ...]   (default: all)
        e.g. python tool\\generate_dagbani_speech.py hausa_mms twi_mms
"""

from __future__ import annotations

import datetime as _dt
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from transformers import AutoTokenizer, VitsModel

ASSETS = Path(__file__).resolve().parent.parent / "assets" / "audio"

# ---------------------------------------------------------------- the scripts
# Keys are the VoiceRequest ids; values are the exact drafts from
# `speech_bank.dart` (kept verbatim, including the project's draft status).
# Em-dashes become commas: the tokenizer has no entry for '—' and the pause
# it encodes is what we actually want.

BANKS: dict[str, dict[str, object]] = {
    "dagbani_mms": {
        "model": "IanKobby/mms-tts-dag-ghana",
        "upstream": "facebook/mms-tts-dag",
        "phrases": {
            # ------------------------------------------------------- audio topics
            "child_danger_signs": (
                "Ni bini maa ti niŋ ka o nui tana bee ka o nu tana, o yiɣiri, o "
                "ti zuɣa, o wum kpibu, bee o maani nɔri ŋɔ zaɣa — yi tiŋ bɛ ni "
                "kpeeni pam. Tɔ di mali kpeenim maa nyɛla din gbanŋɛ. Bini maa "
                "bɔri sɔŋsi ŋɔ."
            ),
            "newborn_danger_signs": (
                "Ni bini kpalansi maa ti niŋ ka o nu tana, o ɣiri tɔɣi bee o "
                "gbili, o ti zuɣa, o wum kpibu, o ti yɛɣiri pam bee o ti bini, o "
                "ti ɣari yaa-ŋa bee nini, bee o tuli kpamba ti kɔbigu bee o ti "
                "yiɣiri — yi tiŋ bɛ ni kpeeni pam. Bini kpalansi maa bɛ ni kpeenim "
                "tɔ zugiri, di ti bɛ mali ni tɔ mali ŋaani."
            ),
            "mother_danger_signs": (
                "Ni naɣa maa ti kɔbigu pam, o ti m bɛ laɣim pam, o ti bini pam, "
                "o ti kɔbigu taba pam, o ti zuɣa, bee o ti yiɣiri ni bini maa — yi "
                "tiŋ bɛ ni kpeeni pam. Ni o bɛ ni tuhi bini, ka bini maa tuhi ti "
                "laɣim ni yili maa, yi tiŋ kpeeni din yi na. Tɔ di mali kpeenim "
                "ka tɔ tuhi laɣim maa."
            ),
            "feeding": (
                "Tiam kpalansi kpe maa kuli nyini, a tɔri bini — ami, tuhim. Din yi "
                "ti kpeita, tiam tuɣa nini kama anahi puuni ti maani, ka a "
                "naɣisi ti niriba shɛli nyɛla di bɛ ni bini. Tiam nyini ka bini ŋɔ "
                "ti bɛ mali ni bini titali. Bini bɛ mali ni nuhu shɛli bɛ ni tiri, "
                "o ti nɔri."
            ),
            "referral": (
                "Sɔŋsi bɛ maa nyɛla nini ti ni tooi ti shɛli ka tiŋ maa bɛ ni "
                "niŋ shɛli, amaa tiŋ bɛ tiŋ maa ti ni tooi. Yi tiŋ bɛ ni kpeeni "
                "ni bini bɛ ti m-paai ka di yɛli ni ŋɔ — din yi na maa yi kpeeni "
                "nyɛla din gbanŋɛ. Tiam tuhi telephone bini maa bee pepa bini maa, "
                "ka a tiŋ di na kpeeni. Ni bini kpeenim ti m-paai ni tihi, yɛli "
                "ti sɔŋsi nira maa; bɛ bɛ ni laɣim shɛli din ni sɔŋ."
            ),
            # --------------------------------------------------- triage questions
            "q_newborn.feed": "Bini kpalansi maa ti nu tana",
            "q_newborn.fast": "Bini kpalansi maa ɣiri tɔɣi bee ka o gbili",
            "q_newborn.fits": "Bini kpalansi maa ti zuɣa",
            "q_newborn.sleepy": "Bini kpalansi maa wum kpibu pam bee ka o ti mɔri",
            "q_newborn.temp": "Bini kpalansi maa bini pam bee ka o ti bini pam",
            "q_newborn.yellow": "Bini kpalansi maa yaa-ŋa bee nini ɣari",
            "q_newborn.cord": "Tuli kpamba maa kɔbigu, o pɔŋ, bee o yiɣiri ni bini",
            "q_newborn.vomit": "Bini kpalansi maa yiɣiri bini maa pam",
            "q_child.drink": "Bini maa ti ni tooi nu tana bee ka o nu",
            "q_child.vomit": "Bini maa yiɣiri bini maa pam",
            "q_child.fits": "Bini maa ti zuɣa",
            "q_child.sleepy": "Bini maa wum kpibu pam bee ka o ti mɔri",
            "q_child.breath": "Bini maa ɣiri tɔɣi bee ka o ti ɣiri ti tuhi",
            "q_child.blood": "Nɔri bɛ bini maa tuhi",
            "q_child.thin": "Bini maa ti pɔŋ nini pam, bee o ti nɔri pɔŋ",
            "q_child.fever": "Bini maa ti bini ti pii dabaasi anahi",
            "q_mother.bleed": "Naɣa maa kɔbigu pam",
            "q_mother.head": "Naɣa maa m bɛ laɣim pam ti o gɔri ti ti mali yɛn",
            "q_mother.fever": "Naɣa maa bini pam",
            "q_mother.pain": "Naɣa maa ti kɔbigu taba pam",
            "q_mother.fits": "Naɣa maa ti zuɣa",
            "q_mother.smell": "Bini yiɣiri bɛ bini maa",
            "q_mother.move": "Ni o bɛ ni tuhi bini, bini maa tuhi ti laɣim ni yili maa",
            "q_mother.vomit": "Naɣa maa yiɣiri bini maa pam",
            # --------------------------------------------- triage-level messages
            "level_urgent": (
                "Yi tiŋ bɛ ni kpeeni pam. Tɔ di mali kpeenim maa nyɛla din gbanŋɛ."
            ),
            "level_priority": (
                "Tɔ sɔŋsi nira maa ti ti bini maa. Maani sɔŋsi tiŋ maa, ka yi tiŋ "
                "labina dabaasi ata nyaaŋa."
            ),
            "level_watch": (
                "Tin yaa ka ti maani sɔŋsi tiŋ maa. Gbilsim niŋ kpeenim. Ni bini maa "
                "ti niŋ tuma, yi tiŋ labina."
            ),
            "level_routine": (
                "Bini maa nyɛla din yaa. Ti maani sɔŋsi tiŋ maa ka o nu tana."
            ),
            # ----------------------------------------------- caregiver verdicts
            "caregiver_verdict_urgent": (
                "Yi tiŋ bɛ ni kpeeni pam. Bini maa zuɣu m-beni. Tɔ di mali kpeenim "
                "maa nyɛla din gbanŋɛ. Ni CHPS tiŋ maa kpari, yi tiŋ alaafee yili "
                "bee ashibiti titali."
            ),
            "caregiver_verdict_caution": (
                "Ti sɔŋsi nira maa ni kpeenim laɣim. Mi bɛ mi bini shɛŋa. Yi tiŋ "
                "labina ni tiŋ maa dabaasi ayi puuni."
            ),
            "caregiver_verdict_fine": (
                "Tin yaa ka ti maani sɔŋsi tiŋ maa. Bini maa zuɣu maa bɛni. Ti "
                "maani sɔŋsi tiŋ maa, ka ti labina tooni."
            ),
            # ------------------------------------------------ nurse-words frame
            "nurse_intro": "N ni nya bini shɛŋa n-yɛliya.",
            "nurse_unsure": "Mi bɛ mi bini shɛŋa ŋɔ.",
            "nurse_close": "N yɛn yɛliya bini kam ni daa piligi shɛm.",
            # --------------------------------------------------------- standalone
            "setup_preview_Dagbani": "Yi tiŋ bɛ ni kpeeni pam",
            "voice_test_Dagbani": (
                "Ni bini maa ti niŋ ka o nui tana, yi tiŋ bɛ ni kpeeni pam."
            ),
        },
    },
    "hausa_mms": {
        "model": "laztopaz/mms-tts-hau-custom",
        "upstream": "facebook/mms-tts-hau",
        "phrases": {
            # ------------------------------------------------------- audio topics
            "child_danger_signs": (
                "Idan yaro ba zai iya sha ko shan nono ba, ko yana fitar da "
                "abinci gaba ɗaya, ko yana tautsiya, ko ya kwanta ba za a iya "
                "farkar da shi ba, ko numfashinsa ya yi sauri ko ya yi wahala, "
                "ko akwai jini a cikin latto — ku tafi asibiti yanzu. Kar ku "
                "jira har gobe. Waɗannan alamu sun nuna cewa yaron buƙatar "
                "taimako take a yau."
            ),
            "newborn_danger_signs": (
                "Idan jariri ba ya shan nono da kyau, ko numfashinsa ya yi "
                "sauri ko yana yi wahala, ko yana tautsiya, ko ya kwanta ba za "
                "a iya farkar da shi ba, ko jikinsa ya yi zafi sosai ko sanyi "
                "sosai, ko tafafunsa ko ƙafafunsa sun yi rawaya, ko makogwaronsa "
                "ta yi ja ko ta ɓata wari — ku tafi asibiti yanzu. Jariri ƙarami "
                "na iya yin rashin lafiya cikin gaggawa, saboda haka kar ku "
                "jira."
            ),
            "mother_danger_signs": (
                "Idan mace na zubar da jini sosai, ko ciwon kai mai ƙarfi tare "
                "da lalacewar gani, ko zazzabi mai tsanani, ko ciwon ciki mai "
                "ƙarfi, ko tautsiya, ko fitar da abu mai ɓata wari — ku tafi "
                "asibiti yanzu. Idan tana ciki kuma jaririn ya ragu da motsi "
                "fiye da yadda yake a baya, ku tafi a ranar nan. Kar ku jira "
                "har ciwon ya wuce."
            ),
            "feeding": (
                "Ba nono kawai har watanni shida — ba ruwa, ba fura. Daga "
                "watanni shida, ku ba da fura mai ƙauri sau huɗu a rana, ku "
                "kuma ƙara man gyada, ƙwai, kifi ko wake idan suna nan. Ku ci "
                "gaba da shan nono har shekaru biyu. Yaro da ke cin abinci "
                "akai-akai, girma yake yi."
            ),
            "referral": (
                "Nufin turo ita ce, asibitin na iya yin abin da wannan gida ba "
                "zai iya ba. Ku tafi da zarar an ce muku — ranar nan idan "
                "lamari ne na gaggawa. Ku ɗauki waya ko takardar lamba, ku "
                "nuna ta a ƙofa. Idan sufuri shine matsalar, ku faɗi wa "
                "ma'aikacin lafiya; akwai hanyoyin taimako."
            ),
            # --------------------------------------------------- triage questions
            "q_newborn.feed": "Jaririn ba ya shan nono da kyau",
            "q_newborn.fast": "Numfashin jaririn ya yi sauri ko yana yi wahala",
            "q_newborn.fits": "Jaririn na tautsiya",
            "q_newborn.sleepy": "Jaririn yana yawan kwanci, farkar da shi yake da wahala",
            "q_newborn.temp": "Jikin jaririn ya yi zafi sosai ko sanyi sosai",
            "q_newborn.yellow": "Tafafunsa ko ƙafafunsa sun yi rawaya",
            "q_newborn.cord": "Makogwaro ta yi ja, ta kumbura, ko ta ɓata wari",
            "q_newborn.vomit": "Jaririn na fitar da abinci gaba ɗaya",
            "q_child.drink": "Yaro ba zai iya sha ko shan nono ba",
            "q_child.vomit": "Yaron na fitar da abinci gaba ɗaya",
            "q_child.fits": "Yaron na tautsiya",
            "q_child.sleepy": "Yaron yana yawan kwanci, farkar da shi yake da wahala",
            "q_child.breath": "Numfashin yaron ya yi sauri ko yana yi wahala",
            "q_child.blood": "Akwai jini a cikin latto",
            "q_child.thin": "Yaron ya yi rauni sosai, ko ƙafafun sa sun kumbura",
            "q_child.fever": "Zazzabin yaron ya wuce kwanaki uku",
            "q_mother.bleed": "Mace na zubar da jini sosai",
            "q_mother.head": "Ciwon kai mai ƙarfi tare da lalacewar gani",
            "q_mother.fever": "Zazzabi mai tsanani",
            "q_mother.pain": "Ciwon ciki mai ƙarfi",
            "q_mother.fits": "Mace na tautsiya",
            "q_mother.smell": "Fitowar abu mai ɓata wari",
            "q_mother.move": "Idan tana ciki, jaririn ya ragu da motsi",
            "q_mother.vomit": "Macen na fitar da abinci gaba ɗaya",
            # --------------------------------------------- triage-level messages
            "level_urgent": "Ku tafi asibiti yanzu. Kar ku jira har gobe.",
            "level_priority": (
                "An ba da magani. Ku ba da shi gaba ɗaya, ku koma bayan kwana uku."
            ),
            "level_watch": (
                "Ku kula da mutumin a gida, ku sa ido sosai. Idan lafiyar ta "
                "tabarbare, ku koma asibiti."
            ),
            "level_routine": (
                "Duk lafiya take. Ku ci gaba da kyautata abinci da kulawa."
            ),
            # ----------------------------------------------- caregiver verdicts
            "caregiver_verdict_urgent": (
                "Ku tafi asibiti yanzu. Alamomin hadari sun bayyana. Kar ku "
                "jira har gobe. Idan ofishin CHPS ya rufe, ku tafi cibiyar "
                "lafiya ko babbar asibiti."
            ),
            "caregiver_verdict_caution": (
                "Ku ziyarci mai kula da lafiyarku nan ba da jimawa ba. Wasu "
                "amsoshi ba su bayyana ba. Ku kai wannan mutum asibiti a ziyara "
                "ta gaba, ku kuma sa ido sosai har kwana biyu."
            ),
            "caregiver_verdict_fine": (
                "Ku ci gaba da kula da lafiya akai-akai. Babu wata alamar "
                "hadari da ta bayyana. Ku ci gaba da ciyar da shi, shan ruwa, "
                "ku kuma duba shi gobe."
            ),
            # ------------------------------------------------ nurse-words frame
            "nurse_intro": "Waɗannan abubuwan da na gani:",
            "nurse_unsure": "Waɗanda ban tabbata ba:",
            "nurse_close": "Zan faɗi yadda kowane alamu ya fara.",
            # --------------------------------------------------------- standalone
            "setup_preview_Hausa": "Ku tafi asibiti yanzu",
            "voice_test_Hausa": "Idan yaranku ba ta iya sha ko nono, je asibitin yanzu.",
        },
    },
    "twi_mms": {
        "model": "IanKobby/mms-tts-twi-ghana",
        "upstream": "facebook/mms-tts-twi",
        "phrases": {
            # ------------------------------------------------------- audio topics
            "child_danger_signs": (
                "Sɛ akwadaa ntumi nnom nsuo anaasɛ ɔnnom nono, anaasɛ ɔto "
                "aduane nyinaa, anaasɛ sɛsɛa si no, anaasɛ ɔda dɛ a ɛyɛ den sɛ "
                "wobɛbue no, anaasɛ n'ehome yɛ ntɛm anaasɛ ɛyɛ no den, anaasɛ "
                "mogya wɔ ne dua mu — kɔ ayaresabea ntɛm ara. Ntwɛn nyɛ anɔpa. "
                "Saa nsɛnkyerɛnne yi kyerɛ sɛ akwadaa no hia mmoa nnɛ."
            ),
            "newborn_danger_signs": (
                "Sɛ abofra ketewa annom nono yie, anaasɛ n'ehome yɛ ntɛm "
                "anaasɛ ɛyɛ no den, anaasɛ sɛsɛa si no, anaasɛ ɔda dɛ a ɛyɛ den "
                "sɛ wobɛbue no, anaasɛ ne nipadua ayɛ hyew paa anaasɛ ɔserew "
                "paa, anaasɛ ne nsa ase ne nan ase ayɛ abere, anaasɛ ne pampɔn "
                "no ayɛ kɔkɔɔ anaasɛ anyare — kɔ ayaresabea ntɛm. Abofra ketewa "
                "betumi anyare ntɛm pa, enti ntwɛn."
            ),
            "mother_danger_signs": (
                "Sɛ ɔbaa no mogya re gu no kɛseɛ, anaasɛ ne ti yɛ no yaw den a "
                "ne ani nnhu pɛpɛɛpɛ, anaasɛ ɔyɛ hyew denden, anaasɛ ne yafunu "
                "yɛ no yaw den, anaasɛ sɛsɛa si no, anaasɛ afoforo a ɛfiri ne "
                "mu no ayɛ hu — kɔ ayaresabea ntɛm. Sɛ ɔyɛ ɔokafo na abofra no "
                "rebu bio sɛdeɛ ɛbɛyɛ pɛ, kɔ saa ara da no. Ntwɛn nyɛ anɔpa."
            ),
            "feeding": (
                "Fa nono nko ara ma no kɔsi bosome nsia — nsuo biara, koko "
                "biara nni hɔ. Firi bosome nsia, fa koko a emu yɛ den ma no "
                "mpɛn nan da biara, na fa nkate, kosua, nam anaasɛ abubuo ka "
                "ho berɛ a wobɛnya. San ma no nono kɔsi mfeɛ mmienu. Akwadaa a "
                "ɔdi aduane mpɛn pii, ɔnyin."
            ),
            "referral": (
                "Wɔde wo referral kɔ ayaresabea a ɛso sen deɛ ɛwɔ mpɔtam hɔ, "
                "ɛfiri sɛ ɛhɔ na wɔtumi yɛ biribi a yɛntumi nyɛ wɔ ha. Kɔ ntɛm "
                "ara sɛ wɔka kyerɛ wo — da no ara sɛ ɛyɛ ntɛm. Fa wote yi "
                "anaasɛ krataa no kɔ, na kyerɛ wɔn a wɔwɔ anim. Sɛ akwan ne "
                "tebea na ɛma wontumi nkɔ a, ka kyerɛ akwankwaa no; yɛwɔ "
                "akwan a yɛfa so boa."
            ),
            # --------------------------------------------------- triage questions
            "q_newborn.feed": "Abofra no nnom nono yie",
            "q_newborn.fast": "N'ehome yɛ ntɛm anaasɛ ɛyɛ no den",
            "q_newborn.fits": "Sɛsɛa asi no",
            "q_newborn.sleepy": "Ɔda dɛ, ɛyɛ den sɛ wobɛbue no",
            "q_newborn.temp": "Ne nipadua ayɛ hyew paa anaasɛ ɔserew paa",
            "q_newborn.yellow": "Ne nsa ase ne nan ase ayɛ abere",
            "q_newborn.cord": "Ne pampɔn no ayɛ kɔkɔɔ, ayɛ kɛseɛ, anaasɛ anyare",
            "q_newborn.vomit": "Ɔto aduane nyinaa",
            "q_child.drink": "Akwadaa no ntumi nnom nsuo anaasɛ nono",
            "q_child.vomit": "Ɔto aduane nyinaa",
            "q_child.fits": "Sɛsɛa asi no",
            "q_child.sleepy": "Ɔda dɛ, ɛyɛ den sɛ wobɛbue no",
            "q_child.breath": "N'ehome yɛ ntɛm anaasɛ ɛyɛ no den",
            "q_child.blood": "Mogya wɔ ne dua mu",
            "q_child.thin": "Akwadaa no ayɛ baree pa ara, anaasɛ ne nan ayɛ kɛseɛ",
            "q_child.fever": "Ɔyɛ hyew kyɛn nnansa",
            "q_mother.bleed": "Ne mogya re gu no kɛseɛ",
            "q_mother.head": "Ne ti yɛ no yaw den, ne ani nso annhu pɛpɛɛpɛ",
            "q_mother.fever": "Ne nipadua ayɛ hyew paa",
            "q_mother.pain": "Ne yafunu yɛ no yaw den",
            "q_mother.fits": "Sɛsɛa asi no",
            "q_mother.smell": "Afoforo a ɛfiri ne mu no ayɛ hu",
            "q_mother.move": "Sɛ ɔyɛ ɔokafo a, abofra no rebu bio sɛdeɛ ɛbɛyɛ pɛ",
            "q_mother.vomit": "Ɔto aduane nyinaa",
            # --------------------------------------------- triage-level messages
            "level_urgent": "Kɔ ayaresabea ntɛm ara. Ntwɛn nyɛ anɔpa.",
            "level_priority": (
                "Wɔama no aduro no. Fa aduro no nyinaa ma no, na san kɔ "
                "ayaresabea akyire nna mmiɛnsa."
            ),
            "level_watch": (
                "Hwɛ no yie wɔ fie. Sɛ ne tebea yɛ no fɛw a, san kɔ ayaresabea."
            ),
            "level_routine": (
                "Biribiara yɛ hɔ. San ma no nono, na toaso akwahosan no so."
            ),
            # ----------------------------------------------- caregiver verdicts
            "caregiver_verdict_urgent": (
                "Kɔ ayaresabea ntɛm ara. Nsɛnkyerɛnne a ɛkyerɛ ɔhaw no asisi. "
                "Ntwɛn nyɛ anɔpa. Sɛ CHPS beaeɛ no adan mu a, kɔ ayaresabea "
                "biara a ɛbɛn wo."
            ),
            "caregiver_verdict_caution": (
                "Hwɛ wo CHW no ntɛm. Mmoa no bi nkyerɛ pefee. Fa obi no kɔ "
                "ayaresabea wɔ berɛ a wɔahyɛ no so, na hwɛ no yiye nnafua "
                "mmienu."
            ),
            "caregiver_verdict_fine": (
                "Toaso akwahosan pa so. Nsɛnkyerɛnne biara nni hɔ. San ma no "
                "nono, ma no nsuo nom, na san hwɛ no ɔkyena."
            ),
            # ------------------------------------------------ nurse-words frame
            "nurse_intro": "Nea mehunuu:",
            "nurse_unsure": "Nea mennim:",
            "nurse_close": "Mebɛka sɛdeɛ nsɛnkyerɛnne biara fii aseɛ.",
            # --------------------------------------------------------- standalone
            "setup_preview_Twi": "Kɔ ayaresabea ntɛm ara",
            "voice_test_Twi": (
                "Sɛ akwadaa ntumi nnom nsuo anaasɛ nono a, kɔ ayaresabea ntɛm ara."
            ),
        },
    },
}


def _tidy(text: str) -> str:
    return text.replace("—", ",").replace("  ", " ").strip()


def generate(bank: str) -> None:
    spec = BANKS[bank]
    model_id: str = spec["model"]
    upstream: str = spec["upstream"]
    phrases: dict[str, str] = spec["phrases"]
    out_dir = ASSETS / bank
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[{bank}] Loading {model_id} …")
    tokenizer = AutoTokenizer.from_pretrained(model_id)
    model = VitsModel.from_pretrained(model_id)
    model.eval()
    rate = model.config.sampling_rate
    print(f"[{bank}] Loaded. Sampling rate: {rate} Hz")

    pad = np.zeros(int(rate * 0.15), dtype=np.float32)
    manifest: dict[str, dict[str, object]] = {}

    for audio_id, raw in phrases.items():
        text = _tidy(raw)
        inputs = tokenizer(text, return_tensors="pt")
        with torch.no_grad():
            out = model(**inputs).waveform
        wav = out.squeeze().numpy().astype(np.float32)

        # Peak-normalize so every clip plays at a comparable loudness, then
        # add a small breathing pad on both ends.
        peak = float(np.max(np.abs(wav))) or 1.0
        wav = wav / peak * 0.85
        wav = np.concatenate([pad, wav, pad])

        target = out_dir / f"{audio_id}.wav"
        sf.write(target, wav, rate, subtype="PCM_16")
        manifest[audio_id] = {
            "seconds": round(len(wav) / rate, 2),
            "bytes": target.stat().st_size,
        }
        print(
            f"[{bank}]   {audio_id}.wav  "
            f"{len(wav) / rate:.1f}s  {target.stat().st_size // 1024} KB"
        )

    total = sum(int(m["bytes"]) for m in manifest.values())
    (out_dir / "manifest.json").write_text(
        json.dumps(
            {
                "generated": _dt.date.today().isoformat(),
                "model_mirror": model_id,
                "upstream": upstream,
                "sampling_rate": rate,
                "total_bytes": total,
                "clips": manifest,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"[{bank}] Done. {len(manifest)} clips, {total // 1024} KB total.")

    # Release the model before loading the next bank's.
    del model, tokenizer


def main() -> None:
    banks = sys.argv[1:] or list(BANKS)
    unknown = [b for b in banks if b not in BANKS]
    if unknown:
        raise SystemExit(
            f"Unknown bank(s): {unknown}. Known: {list(BANKS)}."
        )
    for bank in banks:
        generate(bank)


if __name__ == "__main__":
    main()

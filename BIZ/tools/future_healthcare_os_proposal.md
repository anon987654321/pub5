# Fremtidens helse-OS — forslagsnotat

Kilde for `future_healthcare_os.html`; etterfulgte operatørens ordre
8. november 2026: «for pubhealthcare the plan is also to create a future
healthcare OS modelled after openbsd, rails/rhoda, and our own MASTER».

## Postulat

Helse-IT i Norge er kjøpt som systemer og levd som patcharbeid. Planen bygger
et helse-OS der tre discipliner er bærebjelker: OpenBSDs kjerne-disiplin
(minst mulig angrepsflate, kapabilitet i stedet for tillit, revisjonsspor i
kjernen), Rails/Rhoda-konvensjonene i applikasjonslaget (konvensjon før
konfigurasjon, API før grensesnitt), og MASTERs lovmaskin fra eget hus
(kliniske regler som maskinlesbare lover med kjørbare sjekker, ikke PDF-er).

## Kapittel

1. Sammendrag — visjon, misjon, innovasjon, kundefordel, hvorfor nå
2. Markedsanalyse — marked, segmenter, konkurranse, fortrinn, innsikt, salg
3. Teknologi og innovasjon — kjernen, applikasjonslaget, lovmaskinen
4. Forretningsmodell — lisens, tjenester, lønnsomhet, enhetsøkonomi
5. Utviklingsveikart — milepæler med måltall
6. Finansieringsbehov — NOK 500 000, allokering, tre-års budsjetter, risiko
7. Team og kompetanse — kjerneutvikler, kliniker, lovarkitekt
8. Bærekraft og samfunnsansvar — pasientsikkerhet, etikk, mål

## Fundament (verifiserte tall)

- Totalt kapitalbehov: NOK 500 000 (Innovasjon Norge 350 000,
  privat risikokapital 150 000).
- Resultatbudsjett (NOK millioner): 2026 −4,0; 2027 0,9; 2028 7,8 før skatt.
- Likviditetens utgående saldo: 0,3 / 0,8 / 5,8.
- Pilot: to kommuner og ett helseforetak på FHIR-grensesnittet.
- Lovmaskinen starter med 40 kliniske lover, hver med kjørbare sjekker.

## Lover planen må tåle

Samme lovsett som de andre planene: Strunk-higiena, guillemeter, tabelltall,
setningscase, sumkontrollerte budsjetter — håndhevet av `bp_check.mjs`.

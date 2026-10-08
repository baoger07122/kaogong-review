# Canonical merged question-bank JSON (v1)

This contract describes one canonical paper whose questions and shared materials have already been reviewed and deduplicated by the preparation workflow. The app imports the supplied canonical rows; it does not merge source papers, compare answer content, or deduplicate questions.

## Compatibility

- Keep format as kaogong-question-bank and schemaVersion as 1.
- Provenance is an optional v1 extension. Existing v1 files without sourcePapers and provenance remain valid.
- paper is the single canonical paper. sourcePapers is an optional top-level metadata list, not a second set of paper/question rows.
- If sourcePapers is present, each entry must include originalFileName and a 64-character hexadecimal originalFileSHA256.
- The importer validates the SHA-256 field's shape. The source PDFs are not embedded in the package, so the importer cannot recompute these hashes.
- The legacy optional batch field remains a separate batch index contract. A batch that lists source papers side by side is not a canonical merged paper.
- Current limits: JSON file ≤64 MiB, each decoded image ≤16 MiB, and all decoded images ≤48 MiB total. The import preview shows the file and image sizes against these limits.

## Exact provenance fields

    sourcePapers?: SourcePaper[]

    SourcePaper = {
      id: string,                       // stable source-paper ID
      provinceCode?: string,
      provinceName?: string,
      batchID?: string,
      batchName?: string,
      originalFileID?: string,
      originalFileName?: string,        // required when sourcePapers is present
      originalFileSHA256?: string       // required when sourcePapers is present; 64 hex characters
    }

    QuestionBankProvenance = {
      sourcePaperID: string,            // must match a sourcePapers[].id
      provinceCode?: string,
      provinceName?: string,
      sourceQuestionNumber?: integer,   // required for question provenance
      sourceQuestionNumbers?: integer[],// material provenance needs a number or a nonempty list
      originalPage?: string,            // required for every provenance entry; ranges may be strings
      evidence?: string
    }

Add provenance?: QuestionBankProvenance[] to each canonical question and material. A canonical question may have several provenance entries when it is the same verified question in multiple source papers. Each question provenance entry must include sourceQuestionNumber and originalPage. Each material provenance entry must include originalPage and either sourceQuestionNumber or a nonempty sourceQuestionNumbers list; use the list when one shared source material covers several original questions. Every sourcePaperID must resolve to a top-level sourcePapers[].id. The importer rejects missing source filenames/checksums, invalid SHA shapes, unresolved source IDs, missing original number/page mappings, and non-positive original question numbers before writing.

The canonical paper may also include optional provinceCode and provinceName for a single-province paper. Do not infer province, batch, or original file ID from titles or file names.

## Stable identity and deduplication rules

- Keep paper.id, module.id, material.id, question.id, and asset.id stable across revisions. All paperID, moduleID, materialID, owner, and asset references must point to those IDs.
- question.number is the display number in the current canonical paper. A later revision may change it. Preserve original question numbers in provenance.
- Keep a repeated, verified question once in questions and attach one provenance entry per source occurrence.
- Do not deduplicate questions when option order, answer, or meaning conflicts. Preserve separate canonical question IDs and evidence for unresolved conflicts.
- Shared material text can have multiple provenance entries while each distinct question referring to it remains a separate question.
- The reader keeps provenance collapsed by default. “材料来源” and “题目来源” reveal source paper, original question/page, original filename, checksum, and supplied evidence.
- Replacing a paper with changed stable IDs can strand prior answer state or ink. The app warns about ID changes and does not migrate or delete saved doodle records.

## Example

This small example has one canonical paper and one canonical question sourced from two PDFs. The checksums below are illustrative 64-character placeholders; production JSON must contain the SHA-256 values of the actual source PDF bytes. It omits images, so assets is empty.

    {
      "format": "kaogong-question-bank",
      "schemaVersion": 1,
      "paper": {
        "id": "canonical-2025-joint",
        "title": "2025年联考行测",
        "year": 2025,
        "examType": "行测",
        "volume": "",
        "source": "canonical-preparation",
        "importVersion": "1"
      },
      "sourcePapers": [
        {
          "id": "source-a",
          "provinceCode": "AA",
          "provinceName": "甲省",
          "batchID": "2025-joint",
          "batchName": "2025联考",
          "originalFileID": "file-a",
          "originalFileName": "2025-甲省.pdf",
          "originalFileSHA256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        {
          "id": "source-b",
          "provinceCode": "BB",
          "provinceName": "乙省",
          "batchID": "2025-joint",
          "batchName": "2025联考",
          "originalFileID": "file-b",
          "originalFileName": "2025-乙省.pdf",
          "originalFileSHA256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
      ],
      "modules": [
        {
          "id": "module-language",
          "paperID": "canonical-2025-joint",
          "sequence": 1,
          "title": "言语理解与表达",
          "instruction": "",
          "originalPage": "1"
        }
      ],
      "materials": [
        {
          "id": "material-01",
          "paperID": "canonical-2025-joint",
          "moduleID": "module-language",
          "type": "文字材料",
          "text": "共同材料正文。",
          "imageAssetID": "",
          "applicableQuestions": "12",
          "originalPage": "4",
          "provenance": [
            {
              "sourcePaperID": "source-a",
              "provinceCode": "AA",
              "provinceName": "甲省",
              "sourceQuestionNumbers": [18],
              "originalPage": "4",
              "evidence": "原卷第4页材料段"
            },
            {
              "sourcePaperID": "source-b",
              "provinceCode": "BB",
              "provinceName": "乙省",
              "sourceQuestionNumbers": [18],
              "originalPage": "4",
              "evidence": "原卷第4页材料段"
            }
          ]
        }
      ],
      "questions": [
        {
          "id": "question-12",
          "paperID": "canonical-2025-joint",
          "moduleID": "module-language",
          "number": 12,
          "subject": "言语理解",
          "type": "逻辑填空",
          "materialID": "material-01",
          "stem": "根据材料选择最恰当的一项。",
          "stemImageAssetID": "",
          "options": [
            { "id": "A", "text": "选项一", "imageAssetID": "" },
            { "id": "B", "text": "选项二", "imageAssetID": "" }
          ],
          "answer": "A",
          "explanation": "",
          "originalPage": "5",
          "provenance": [
            {
              "sourcePaperID": "source-a",
              "provinceCode": "AA",
              "provinceName": "甲省",
              "sourceQuestionNumber": 18,
              "originalPage": "5",
              "evidence": "题干、选项顺序和答案一致"
            },
            {
              "sourcePaperID": "source-b",
              "provinceCode": "BB",
              "provinceName": "乙省",
              "sourceQuestionNumber": 18,
              "originalPage": "5",
              "evidence": "题干、选项顺序和答案一致"
            }
          ]
        }
      ],
      "assets": []
    }

The preview lists source PDFs with filenames and checksums, counts question/material provenance mappings, and displays image/file limits. After import, the source list is persisted with the canonical paper payload, and each question/material payload retains its provenance array. No question or material rows are created for the listed source papers.

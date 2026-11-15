//
//  QeniroPDF-Bridging-Header.h
//  PDFium C API'sini Swift'e açar. Başlıklar build.sh tarafından Vendor/pdfium/include içine indirilir.
//

#ifndef QeniroPDF_Bridging_Header_h
#define QeniroPDF_Bridging_Header_h

#include "fpdfview.h"
#include "fpdf_edit.h"
#include "fpdf_text.h"
#include "fpdf_save.h"
#include "fpdf_signature.h"

/// FPDF_SaveAsCopy için yazıcı: PDFium yalnızca `base` alanını bilir, `context`
/// Swift tarafındaki veri toplayıcıyı taşır. `base` ilk alan olduğu için
/// WriteBlock'a gelen işaretçi bu yapının başını gösterir.
typedef struct QPDFFileWriter {
    FPDF_FILEWRITE base;
    void *context;
} QPDFFileWriter;

#endif /* QeniroPDF_Bridging_Header_h */

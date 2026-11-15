//
//  QeniroPDFiOS-Bridging-Header.h
//  PDFium C API'sini iOS hedefine açar. Başlıklar build-ios.sh tarafından
//  ../Vendor/pdfium-ios/include içine indirilir. Başlık yoksa (PDFium kurulmamışsa)
//  hiçbir şey eklenmez ve Swift tarafı QPDF_PDFIUM bayrağı olmadan yedek yola düşer.
//

#ifndef QeniroPDFiOS_Bridging_Header_h
#define QeniroPDFiOS_Bridging_Header_h

#if __has_include("fpdfview.h")
#include "fpdfview.h"
#include "fpdf_edit.h"
#include "fpdf_text.h"
#include "fpdf_save.h"

/// FPDF_SaveAsCopy için yazıcı: PDFium yalnızca `base` alanını bilir, `context`
/// Swift tarafındaki veri toplayıcıyı taşır. `base` ilk alan olduğu için
/// WriteBlock'a gelen işaretçi bu yapının başını gösterir.
typedef struct QPDFFileWriter {
    FPDF_FILEWRITE base;
    void *context;
} QPDFFileWriter;
#endif

#endif /* QeniroPDFiOS_Bridging_Header_h */

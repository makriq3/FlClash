package com.makriq.flclash.service

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException

class FilesProvider : DocumentsProvider() {

    companion object {
        private const val DEFAULT_ROOT_ID = "0"
        private const val ROOT_DOCUMENT_ID = "root"
        private const val DOCUMENT_ID_SEPARATOR = ":"

        private val DEFAULT_DOCUMENT_COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_FLAGS,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        private val DEFAULT_ROOT_COLUMNS = arrayOf(
            DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_FLAGS,
            DocumentsContract.Root.COLUMN_ICON,
            DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_SUMMARY,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID
        )
    }

    override fun onCreate(): Boolean {
        return true
    }

    override fun queryRoots(projection: Array<String>?): Cursor {
        return MatrixCursor(projection ?: DEFAULT_ROOT_COLUMNS).apply {
            newRow().apply {
                add(DocumentsContract.Root.COLUMN_ROOT_ID, DEFAULT_ROOT_ID)
                add(DocumentsContract.Root.COLUMN_FLAGS, DocumentsContract.Root.FLAG_LOCAL_ONLY)
                add(DocumentsContract.Root.COLUMN_ICON, R.drawable.ic_service)
                add(DocumentsContract.Root.COLUMN_TITLE, "FlClash")
                add(DocumentsContract.Root.COLUMN_SUMMARY, "Data")
                add(DocumentsContract.Root.COLUMN_DOCUMENT_ID, ROOT_DOCUMENT_ID)
            }
        }
    }


    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<String>?,
        sortOrder: String?
    ): Cursor {
        val result = MatrixCursor(resolveDocumentProjection(projection))
        val parentFile = resolveDocumentFile(parentDocumentId)
        if (!parentFile.isDirectory) {
            throw FileNotFoundException("Parent directory not found")
        }
        parentFile.listFiles()?.forEach { file ->
            try {
                includeFile(result, file)
            } catch (_: FileNotFoundException) {
                // Skip entries that resolve outside the provider root.
            }
        }
        return result
    }

    override fun queryDocument(documentId: String, projection: Array<String>?): Cursor {
        val result = MatrixCursor(resolveDocumentProjection(projection))
        val file = resolveDocumentFile(documentId)
        includeFile(result, file)
        return result
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        val file = resolveDocumentFile(documentId)
        val accessMode = ParcelFileDescriptor.parseMode(mode)
        return ParcelFileDescriptor.open(file, accessMode)
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        return try {
            val parentFile = resolveDocumentFile(parentDocumentId)
            val documentFile = resolveDocumentFile(documentId)
            documentFile == parentFile || documentFile.path.startsWith("${parentFile.path}${File.separator}")
        } catch (_: FileNotFoundException) {
            false
        }
    }

    private fun includeFile(result: MatrixCursor, file: File) {
        result.newRow().apply {
            add(DocumentsContract.Document.COLUMN_DOCUMENT_ID, resolveDocumentId(file))
            add(DocumentsContract.Document.COLUMN_DISPLAY_NAME, file.name)
            add(DocumentsContract.Document.COLUMN_SIZE, file.length())
            add(
                DocumentsContract.Document.COLUMN_FLAGS,
                DocumentsContract.Document.FLAG_SUPPORTS_WRITE or DocumentsContract.Document.FLAG_SUPPORTS_DELETE
            )
            add(DocumentsContract.Document.COLUMN_MIME_TYPE, getDocumentType(file))
        }
    }

    private fun getDocumentType(file: File): String {
        return if (file.isDirectory) {
            DocumentsContract.Document.MIME_TYPE_DIR
        } else {
            "application/octet-stream"
        }
    }

    private fun resolveDocumentProjection(projection: Array<String>?): Array<String> {
        return projection ?: DEFAULT_DOCUMENT_COLUMNS
    }

    private fun resolveBaseDirectory(): File {
        return context?.filesDir?.canonicalFile
            ?: throw FileNotFoundException("Base directory not found")
    }

    private fun resolveDocumentFile(documentId: String): File {
        val baseDirectory = resolveBaseDirectory()
        if (documentId == ROOT_DOCUMENT_ID) {
            return baseDirectory
        }
        val prefix = "$ROOT_DOCUMENT_ID$DOCUMENT_ID_SEPARATOR"
        if (!documentId.startsWith(prefix)) {
            throw FileNotFoundException("Document not found")
        }
        val relativePath = documentId.removePrefix(prefix)
        if (relativePath.isBlank()) {
            return baseDirectory
        }
        val file = File(baseDirectory, relativePath).canonicalFile
        val isWithinBaseDirectory =
            file == baseDirectory || file.path.startsWith("${baseDirectory.path}${File.separator}")
        if (!isWithinBaseDirectory || !file.exists()) {
            throw FileNotFoundException("Document not found")
        }
        return file
    }

    private fun resolveDocumentId(file: File): String {
        val baseDirectory = resolveBaseDirectory()
        val canonicalFile = file.canonicalFile
        if (canonicalFile == baseDirectory) {
            return ROOT_DOCUMENT_ID
        }
        val prefix = "${baseDirectory.path}${File.separator}"
        if (!canonicalFile.path.startsWith(prefix)) {
            throw FileNotFoundException("Document not found")
        }
        return "$ROOT_DOCUMENT_ID$DOCUMENT_ID_SEPARATOR${canonicalFile.path.removePrefix(prefix)}"
    }
}

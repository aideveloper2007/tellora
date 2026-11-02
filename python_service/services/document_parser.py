import os
from typing import Optional
import PyPDF2
from docx import Document
import markdown


class DocumentParser:
    """
    Service for parsing various document formats.
    """
    
    def extract_text(self, file_path: str, filename: str) -> str:
        """
        Extract text from document based on file type.
        """
        file_ext = filename.split('.')[-1].lower()
        
        if file_ext == 'pdf':
            return self._extract_from_pdf(file_path)
        elif file_ext in ['docx', 'doc']:
            return self._extract_from_docx(file_path)
        elif file_ext == 'txt':
            return self._extract_from_txt(file_path)
        elif file_ext in ['md', 'markdown']:
            return self._extract_from_markdown(file_path)
        else:
            raise ValueError(f"Unsupported file type: {file_ext}")
    
    def _extract_from_pdf(self, file_path: str) -> str:
        """Extract text from PDF file"""
        text = ""
        try:
            with open(file_path, 'rb') as file:
                pdf_reader = PyPDF2.PdfReader(file)
                for page in pdf_reader.pages:
                    text += page.extract_text() + "\n"
        except Exception as e:
            raise Exception(f"Error reading PDF: {str(e)}")
        
        return text.strip()
    
    def _extract_from_docx(self, file_path: str) -> str:
        """Extract text from DOCX file"""
        try:
            doc = Document(file_path)
            text = "\n".join([paragraph.text for paragraph in doc.paragraphs])
        except Exception as e:
            raise Exception(f"Error reading DOCX: {str(e)}")
        
        return text.strip()
    
    def _extract_from_txt(self, file_path: str) -> str:
        """Extract text from TXT file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                text = file.read()
        except Exception as e:
            raise Exception(f"Error reading TXT: {str(e)}")
        
        return text.strip()
    
    def _extract_from_markdown(self, file_path: str) -> str:
        """Extract text from Markdown file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                md_text = file.read()
            # Convert markdown to plain text (removes markdown syntax)
            html = markdown.markdown(md_text)
            # Simple HTML tag removal (for better text extraction, use BeautifulSoup)
            import re
            text = re.sub('<[^<]+?>', '', html)
        except Exception as e:
            raise Exception(f"Error reading Markdown: {str(e)}")
        
        return text.strip()

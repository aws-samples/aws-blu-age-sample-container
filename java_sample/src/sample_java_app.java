 /*
 Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 SPDX-License-Identifier: MIT-0

 Permission is hereby granted, free of charge, to any person obtaining a copy of this
 software and associated documentation files (the "Software"), to deal in the Software
 without restriction, including without limitation the rights to use, copy, modify,
 merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
 PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

import java.util.Map;

class bluAgeSample {

    public static void main(String args[]){
        System.out.println("Hello World!");

        Map<String, String> env = System.getenv();
        env.forEach((k, v) -> System.out.println(k + ":" + v));

        try {  
            for (int j = 0; j < 30; j++)  {  
                // The main thread sleeps for the 1000 milliseconds, which is 1 sec  
                // whenever the loop runs  
                Thread.sleep(1000);  
                
                // displaying the value of the variable  
                System.out.println(j);  
            }  
        }  
        catch (Exception expn) {  
            // catching the exception  
            System.out.println(expn);  
        }  
    }  
}

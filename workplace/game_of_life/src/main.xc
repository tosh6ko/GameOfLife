// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width

typedef unsigned char uchar;      //using uchar as shorthand

port p_scl = XS1_PORT_1E;         //interface ports to orientation
port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      // Printing 0-s and 255-s
      //printf( "%d", line[ x ] ); //show image values
    }
    //
    //printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  // printf( "DataInStream: Done...\n" );
  return;
}

// Function to print our matrix to the terminal
void printMatrix(char matrix[IMHT][IMWD])
{
    for(int a=0;a<IMHT;a++)
    {
        for(int b=0;b<IMWD;b++)
        {
            printf("%c ", (matrix[b][a]+'0'));
        }
        printf("\n");
    }
    printf("\n");
}

char isAlive(int neighbour, char previousState)
{
    if(neighbour == 3) return 1;
    if(neighbour == 2 && previousState == 1) return 1;
    return 0;
}

// Function to calculate next state
void calculateNextState(char matrix[IMHT][IMWD])
{
    char previous[IMHT][IMWD];
    for(int a = 0; a < IMHT; a++)
    {
        for(int b = 0; b < IMWD; b++)
        {
            previous[a][b]=matrix[a][b];
        }
    }

    const int neighbourX[8] = {-1,  0, 1, -1, 1, -1,  0, 1};
    const int neighbourY[8] = {-1, -1, -1, 0, 0, 1, 1, 1};
    int numberOfAlive;
    int nX;
    int nY;
    for(int a = 0; a < IMHT; a++)
    {
        for(int b = 0; b < IMWD; b++)
        {
            numberOfAlive = 0;
            for(int i=0;i<8;i++)
            {
                nX = (b+neighbourX[i]+IMWD)%IMWD;
                nY = (a+neighbourY[i]+IMHT)%IMHT;
                if(previous[nY][nX]) numberOfAlive++;
            }

            matrix[a][b] = isAlive(numberOfAlive, previous[a][b]);
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend c_timer)
{
  uchar val;

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Board Tilt...\n" );
  fromAcc :> int value;

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  printf( "Processing...\n" );
  // Send image to worker function
  char matrix[IMHT][IMWD];
  printf( "Printing... \n" );
  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value
      if(val) matrix[y][x] = 1;
      else matrix[y][x] = 0;
    }
  }

  printMatrix(matrix);

  c_timer <: 1;

  // = Number of rounds for which we want to check
  for(int a=0;a<100000;a++)
  {
      calculateNextState(matrix);
      //printMatrix(matrix);
  }

  c_timer <: 2;

  printf( "Saving to file... \n" );
  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
    for( int x = 0; x < IMWD; x++ ) {//go through each pixel per line
        if(matrix[y][x]) c_out <: ((uchar)(0xFF));
        else c_out <: ((uchar)(0x00));
        //c_out <: matrix[y][x]; //send some modified pixel out
    }
  }
  printf( "\nOne processing round completed...\n" );
}

void timer_thread(chanend c_timer)
{
    timer t;
    char timerRunning;
    unsigned int numberOfCycles;
    unsigned int start_time;
    unsigned int end_time;
    unsigned int helper;
    unsigned long long int resultingTime;

    int from_controller;


    const unsigned int period = 100000000; // period of 1s
    const unsigned long long int uint_Max = 4294967295LL;

    while (1)
    {
        select
        {
            case t when timerafter ( uint_Max ) :> void :
                if(timerRunning)
                {
                    numberOfCycles++;
                }
                break;
            case c_timer :> from_controller:
                if(from_controller == 1)
                {
                    t :> start_time;
                    timerRunning = 1;
                    numberOfCycles = 0;
                    helper = start_time-1;
                }
                else if(from_controller == 2)
                {
                    t :> end_time;
                    // Every Cycle is MAX_UNSIGNED_INT - 1, because every cycle is with one lower than MAX_UNSIGNED_INT
                    resultingTime = (uint_Max);
                    resultingTime*= numberOfCycles;
                    resultingTime+=end_time-start_time;
                    printf("\n\n");
                    printf("Number of cycles     : %u\n", numberOfCycles);
                    printf("Time passed (pure)   : %llu\n", resultingTime);
                    printf("Time passed (seconds): %f\n", ((double)resultingTime/period));
                    printf("\n\n");
                    timerRunning = 0;
                }
                break;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];
    }
    _writeoutline( line, IMWD );
    printf( "DataOutStream: Line written to the file...\n" );
  }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here
chan c_inIO, c_outIO, c_control;    //extend your channel definitions here
chan c_timer;

par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    orientation(i2c[0],c_control);        //client thread reading orientation data
    DataInStream(infname, c_inIO);          //thread to read in a PGM image
    DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    distributor(c_inIO, c_outIO, c_control, c_timer);//thread to coordinate work on image
    timer_thread(c_timer);
  }

  return 0;
}